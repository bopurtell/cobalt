open! Core
open Async

module U = Caml_unix
module C1 = Cobalt_app.Session.Open_location

module Open_location = struct
  type position = C1.position = { line : int; column : int }

  type request = C1.request =
    { project_root : string
    ; relative_file : string
    ; position : position option
    }

  type failure = C1.failure =
    | Session_exited
    | Wrong_project of { expected : string; requested : string }
    | Invalid_relative_file of string
    | Target_unavailable of Error.t
    | Invalid_position of Error.t

  let to_error = C1.to_error
end

let max_frame = 32 * 1024
let root_limit = 4096
let fail = failwith

let project_root root =
  if Filename.is_relative root || String.contains root '\000' || String.length root > root_limit
  then fail "Expected an absolute project root of at most 4096 bytes";
  Cobalt_core.Resource.normalize ~cwd:"/" root
;;

module Endpoint = struct
  type t = { base : string; lock : string; socket : string; root : string }
  type owner =
    { endpoint : t; lock_fd : U.file_descr; dir : string; mutable identity : U.stats option }

  let for_project root =
    let base = sprintf "/tmp/cobalt-main-v1-%d" (U.geteuid ()) in
    let key = Stdlib.Digest.(to_hex (string root)) in
    { base; lock = Filename.concat base (key ^ ".lock")
    ; socket = Filename.concat base (key ^ ".sock"); root }
  ;;

  let stat path =
    match U.lstat path with
    | st -> Some st
    | exception U.Unix_error (U.ENOENT, _, _) -> None
  ;;

  let same (a : U.stats) (b : U.stats) =
    Int.equal a.st_dev b.st_dev && Int.equal a.st_ino b.st_ino
  ;;

  let private_as kind perm (st : U.stats) =
    Stdlib.(st.st_kind = kind) && Int.equal st.st_uid (U.geteuid ())
    && Int.equal (st.st_perm land 0o7777) perm
  ;;

  let check_base t =
    if not (Option.exists (stat t.base) ~f:(private_as U.S_DIR 0o700))
    then fail "Main editor runtime directory is missing or not a private owned directory"
  ;;

  let held_lock t ~create =
    let create_file () =
      let fd = U.openfile t.lock [ U.O_RDWR; U.O_CREAT; U.O_EXCL; U.O_CLOEXEC ] 0o600 in
      Exn.protect ~f:(fun () -> U.fchmod fd 0o600) ~finally:(fun () -> U.close fd)
    in
    if create && Option.is_none (stat t.lock)
    then (try create_file () with U.Unix_error (U.EEXIST, _, _) -> ());
    let valid st = private_as U.S_REG 0o600 st && Int.equal st.U.st_nlink 1 in
    let named =
      match stat t.lock with
      | Some st when valid st -> st
      | _ -> fail "Main editor ownership file is missing or unsafe"
    in
    let fd = U.openfile t.lock [ U.O_RDWR; U.O_NONBLOCK; U.O_CLOEXEC ] 0 in
    try
      let opened = U.fstat fd in
      if not (valid opened && same opened named) then fail "Main editor ownership file changed";
      fd
    with exn ->
      U.close fd;
      raise exn
  ;;

  let proof_path dir = Filename.concat dir "s"

  let generation t dir =
    if String.is_prefix dir ~prefix:"s.tmp." && String.length dir = 12
       && String.for_all (String.drop_prefix dir 6) ~f:Char.is_alphanum
    then Filename.concat t.base dir
    else fail "Invalid main editor ownership record"
  ;;

  let read_owner t fd =
    let buf = Bytes.create (max_frame + 1) in
    let rec read off =
      if off > max_frame then fail "Oversized main editor ownership record";
      let n = U.read fd buf off (Bytes.length buf - off) in
      if n = 0 then Stdlib.Bytes.sub_string buf 0 off else read (off + n)
    in
    match Yojson.Safe.from_string (read 0) with
    | `List [ `String root; `String name ] when String.equal root t.root ->
      generation t name
    | _ -> fail "Main editor ownership record does not match this project"
  ;;

  let verified_socket t fd published =
    let dir = read_owner t fd in
    if not (Option.exists (stat dir) ~f:(private_as U.S_DIR 0o700))
    then fail "Main editor socket ownership cannot be verified";
    let proof = proof_path dir in
    if not (private_as U.S_SOCK 0o600 published
            && Option.exists (stat proof) ~f:(fun st ->
              private_as U.S_SOCK 0o600 st && same st published))
    then fail "Main editor socket ownership cannot be verified";
    dir
  ;;

  let remove_if_same path identity =
    if Option.exists (stat path) ~f:(fun st ->
      Stdlib.(st.st_kind = U.S_SOCK) && Int.equal st.st_uid (U.geteuid ()) && same st identity)
    then U.unlink path
  ;;

  let remove_dir_if_empty dir =
    try U.rmdir dir with U.Unix_error ((U.ENOENT | U.ENOTEMPTY | U.EEXIST), _, _) -> ()
  ;;

  let acquire endpoint =
    (try U.mkdir endpoint.base 0o700 with U.Unix_error (U.EEXIST, _, _) -> ());
    check_base endpoint;
    let lock_fd = held_lock endpoint ~create:true in
    try
      if not (Core_unix.flock lock_fd Core_unix.Flock_command.lock_exclusive)
      then fail "A main editor already owns this project";
      Option.iter (stat endpoint.socket) ~f:(fun published ->
        let dir = verified_socket endpoint lock_fd published in
        remove_if_same endpoint.socket published;
        remove_if_same (proof_path dir) published;
        remove_dir_if_empty dir);
      let dir = Core_unix.mkdtemp (Filename.concat endpoint.base "s") in
      { endpoint; lock_fd; dir; identity = None }
    with exn ->
      U.close lock_fd;
      raise exn
  ;;

  let publish owner =
    let proof = proof_path owner.dir in
    let published = U.lstat proof in
    if not (Stdlib.(published.st_kind = U.S_SOCK) && Int.equal published.st_uid (U.geteuid ()))
    then fail "Invalid main editor socket";
    owner.identity <- Some published;
    U.chmod proof 0o600;
    let { endpoint; lock_fd; dir; _ } = owner in
    let data = Yojson.Safe.to_string (`List [ `String endpoint.root; `String (Filename.basename dir) ]) in
    let data = Bytes.of_string data in
    let rec write off =
      let left = Bytes.length data - off in
      if left > 0 then (
        let n = U.write lock_fd data off left in
        if n = 0 then fail "Could not record main editor ownership";
        write (off + n))
    in
    ignore (U.lseek lock_fd 0 U.SEEK_SET : int);
    U.ftruncate lock_fd 0;
    write 0;
    (* The staged name is a hard link proving ownership after a crash. Publish
       without replacing anything, and remove only matching names at teardown. *)
    U.link proof endpoint.socket
  ;;

  let release owner =
    Exn.protect ~finally:(fun () -> U.close owner.lock_fd) ~f:(fun () ->
      Option.iter owner.identity ~f:(fun identity ->
        remove_if_same owner.endpoint.socket identity;
        remove_if_same (proof_path owner.dir) identity);
      remove_dir_if_empty owner.dir)
  ;;

  let locate t =
    check_base t;
    let fd = held_lock t ~create:false in
    Exn.protect ~finally:(fun () -> U.close fd) ~f:(fun () ->
      if Core_unix.flock fd Core_unix.Flock_command.lock_shared
      then fail "No live opted-in main editor for this project";
      match stat t.socket with
      | None -> fail "The main editor is not accepting connections"
      | Some published -> verified_socket t fd published |> proof_path)
  ;;
end

module Wire = struct
  let string key value = key, `String value

  let encode_request ({ project_root; relative_file; position } : Open_location.request) =
    let position = match position with
      | None -> `Null
      | Some { line; column } -> `List [ `Int line; `Int column ]
    in
    `Assoc [ "version", `Int 1; string "action" "open_location"
           ; string "project_root" project_root; string "relative_file" relative_file
           ; "position", position ]
  ;;

  let decode_request : Yojson.Safe.t -> Open_location.request = function
    | `Assoc fields ->
      (match List.sort fields ~compare:(fun (a, _) (b, _) -> String.compare a b) with
       | [ ("action", `String "open_location"); ("position", position)
         ; ("project_root", `String project_root); ("relative_file", `String relative_file)
         ; ("version", `Int 1) ] ->
         let position : Open_location.position option = match position with
           | `Null -> None
           | `List [ `Int line; `Int column ] -> Some { line; column }
           | _ -> fail "Invalid position encoding"
         in
         { project_root; relative_file; position }
       | _ -> fail "Expected a version 1 open_location request")
    | _ -> fail "Invalid request"
  ;;

  let error_text error = String.prefix (Error.to_string_hum error) 2000

  let encode_reply : ((unit, Open_location.failure) Result.t, Error.t) Result.t -> Yojson.Safe.t =
    let open Open_location in
    function
    | Ok (Ok ()) -> `List [ `String "opened" ]
    | Ok (Error Session_exited) -> `List [ `String "session_exited" ]
    | Ok (Error (Wrong_project { expected; requested })) ->
      `List [ `String "wrong_project"; `String expected; `String requested ]
    | Ok (Error (Invalid_relative_file file)) -> `List [ `String "invalid_relative_file"; `String file ]
    | Ok (Error (Target_unavailable e)) -> `List [ `String "target_unavailable"; `String (error_text e) ]
    | Ok (Error (Invalid_position e)) -> `List [ `String "invalid_position"; `String (error_text e) ]
    | Error e -> `List [ `String "transport_error"; `String (error_text e) ]
  ;;

  let decode_reply =
    let open Open_location in
    function
    | `List [ `String "opened" ] -> Ok (Ok ())
    | `List [ `String "session_exited" ] -> Ok (Error Session_exited)
    | `List [ `String "wrong_project"; `String expected; `String requested ] ->
      Ok (Error (Wrong_project { expected; requested }))
    | `List [ `String "invalid_relative_file"; `String file ] -> Ok (Error (Invalid_relative_file file))
    | `List [ `String "target_unavailable"; `String s ] -> Ok (Error (Target_unavailable (Error.of_string s)))
    | `List [ `String "invalid_position"; `String s ] -> Ok (Error (Invalid_position (Error.of_string s)))
    | `List [ `String "transport_error"; `String s ] -> Error (Error.of_string s)
    | _ -> fail "Invalid main editor acknowledgement"
  ;;

  let frame json =
    let body = Yojson.Safe.to_string json in
    let length = String.length body in
    if length > max_frame then fail "Main editor message is too large";
    let header = Bytes.create 4 in
    Stdlib.Bytes.set_int32_be header 0 (Int32.of_int_exn length);
    Bytes.to_string header ^ body
  ;;

  let read_message reader =
    let read bytes =
      match%map Reader.really_read reader bytes with
      | `Ok -> ()
      | `Eof _ -> fail "Incomplete main editor message"
    in
    let header = Bytes.create 4 in
    let%bind () = read header in
    let len = Int32.to_int_exn (Stdlib.Bytes.get_int32_be header 0) in
    if len <= 0 || len > max_frame then fail "Invalid main editor frame size";
    let body = Bytes.create len in
    let%map () = read body in
    Yojson.Safe.from_string (Bytes.to_string body)
  ;;
end

let attempt f =
  match%map Monitor.try_with ~extract_exn:true f with
  | Ok v -> Ok v
  | Error e -> Error (Error.of_exn e)
;;

let bounded seconds message f =
  match%map Clock.with_timeout (Time_float.Span.of_sec seconds) (attempt f) with
  | `Result result -> result
  | `Timeout -> Error (Error.of_string message)
;;

let with_io socket f =
  let fd = Socket.fd socket in
  let reader = Reader.create fd in
  let writer = Writer.create fd in
  Writer.set_raise_when_consumer_leaves writer false;
  Monitor.detach_and_iter_errors (Writer.monitor writer) ~f:ignore;
  Monitor.protect (fun () -> f reader writer) ~finally:(fun () ->
    let%bind () = Writer.close ~force_close:Deferred.unit writer in
    Reader.close reader)
;;

let flush writer data =
  Writer.write writer data;
  match%map Writer.flushed_or_failed_with_result writer with
  | Flushed _ -> ()
  | Consumer_left | Force_closed | Error -> fail "Main editor connection closed during write"
;;

let handle project ~stopping ~active ~on_request socket =
  with_io socket (fun reader writer ->
    let exchange () =
      let%bind request = bounded 2. "Timed out reading main editor request" (fun () ->
        let%bind json = Wire.read_message reader in
        let%map ending = Reader.read_char reader in
        match ending with
        | `Eof -> Wire.decode_request json
        | `Ok _ -> fail "Expected exactly one main editor request")
      in
      let%bind reply = match request with
        | Error e -> return (Error e)
        | Ok request when not (String.equal request.project_root project) ->
          return (Ok (Error (Open_location.Wrong_project { expected = project; requested = request.project_root })))
        | Ok _ when Ivar.is_full stopping ->
          return (Error (Error.of_string "Main editor is shutting down"))
        | Ok _ when !active ->
          return (Error (Error.of_string "Main editor is busy"))
        | Ok request ->
          active := true;
          bounded 3. "Timed out waiting for editor acknowledgement" (fun () ->
            Monitor.protect (fun () -> on_request request)
              ~finally:(fun () -> active := false; Deferred.unit))
      in
      let%map (_ : (unit, Error.t) Result.t) = bounded 1. "Could not write acknowledgement" (fun () ->
        let frame =
          try Wire.encode_reply reply |> Wire.frame with _ ->
            Wire.encode_reply (Error (Error.of_string "Main editor acknowledgement was too large"))
            |> Wire.frame
        in
        flush writer frame)
      in
      ()
    in
    Deferred.any [ Ivar.read stopping; exchange () ])
;;

type t =
  { owner : Endpoint.owner
  ; server : Tcp.Server.unix
  ; stopping : unit Ivar.t
  ; mutable stopped : unit Deferred.t option
  }

let start ~project_root:root ~on_request =
  attempt (fun () ->
    let root = project_root root in
    let%bind owner = In_thread.run (fun () -> Endpoint.acquire (Endpoint.for_project root)) in
    let stopping = Ivar.create () in
    let active = ref false in
    let server = ref None in
    let%bind result = attempt (fun () ->
      let%bind listening = Tcp.Server.create_sock
        ~max_connections:8 ~backlog:8 ~on_handler_error:`Ignore
        (Tcp.Where_to_listen.of_file (Endpoint.proof_path owner.dir))
        (fun _ -> handle root ~stopping ~active ~on_request)
      in
      server := Some listening;
      let%map () = In_thread.run (fun () -> Endpoint.publish owner) in
      { owner; server = listening; stopping; stopped = None })
    in
    match result with
    | Ok t -> return t
    | Error e ->
      Ivar.fill_exn stopping ();
      let%bind () = match !server with
        | None -> Deferred.unit
        | Some server -> Tcp.Server.close ~close_existing_connections:true server
      in
      let%bind () = In_thread.run (fun () -> Endpoint.release owner) in
      Error.raise e)
;;

let stop t =
  match t.stopped with
  | Some stopping -> stopping
  | None ->
    Ivar.fill_exn t.stopping ();
    let stopping =
      let%bind () = Tcp.Server.close ~close_existing_connections:true t.server in
      let%map (_ : (unit, Error.t) Result.t) =
        attempt (fun () -> In_thread.run (fun () -> Endpoint.release t.owner))
      in
      ()
    in
    t.stopped <- Some stopping;
    stopping
;;

let send (request : Open_location.request) =
  let%map result = attempt (fun () ->
    let root = project_root request.project_root in
    let frame = Wire.encode_request { request with project_root = root } |> Wire.frame in
    let%bind socket_path = In_thread.run (fun () -> Endpoint.locate (Endpoint.for_project root)) in
    let%bind socket = Tcp.connect_sock ~timeout:(Time_float.Span.of_sec 1.)
      (Tcp.Where_to_connect.of_file socket_path)
    in
    with_io socket (fun reader writer ->
      bounded 5. "Timed out waiting for main editor acknowledgement" (fun () ->
        let%bind () = flush writer frame in
        Socket.shutdown socket `Send;
        let%map json = Wire.read_message reader in
        Wire.decode_reply json)
      >>| Result.join))
  in
  Result.join result
;;
