open! Core
open! Async

type binding =
  { endpoint : string
  ; project_root : string
  ; run : string option
  }

type attempt =
  { id : string
  ; suite : string
  ; lifecycle : string
  ; outcome : string option
  }

type snapshot =
  { binding : binding
  ; instance_id : string
  ; project_id : string
  ; attempts : attempt list
  ; truncated : bool
  }

type availability =
  | Unavailable of string
  | Fresh of snapshot
  | Stale of snapshot * string

type request =
  { meth : [ `Get | `Post ]
  ; path : string
  ; headers : (string * string) list
  ; body : string
  }

type response = { status : int; body : string }

type peer =
  endpoint:string ->
  timeout:Time_ns.Span.t ->
  stop:unit Deferred.t ->
  request ->
  (response, string) result Deferred.t

let http_peer ~endpoint ~timeout ~stop { meth; path; headers; body } =
  Silver_http.request ~endpoint ~timeout ~stop ~meth ~path ~headers ~body
  >>| Result.map ~f:(fun (status, body) -> { status; body })
;;

let max_identity_bytes = 4096
let max_status_rows = 25
let max_label_bytes = 256

(* Use valid, single-line display text. Silver identifiers used in requests are never
   rewritten; identities containing control or invalid UTF-8 bytes are rejected. *)
let sanitize ~max text =
  let n = String.length text in
  let buf = Buffer.create (Int.min n max) in
  let rec loop i =
    if i < n && i < max
    then (
      let u = Stdlib.String.get_utf_8_uchar text i in
      let len = Stdlib.Uchar.utf_decode_length u in
      if i + len <= max
      then (
        let code = Stdlib.Uchar.utf_decode_uchar u |> Stdlib.Uchar.to_int in
        if not (Stdlib.Uchar.utf_decode_is_valid u)
           || code < 32 || (code >= 127 && code <= 159)
           || code = 0x2028 || code = 0x2029
        then Buffer.add_char buf '?'
        else Buffer.add_substring buf text ~pos:i ~len;
        loop (i + len)))
  in
  loop 0;
  Buffer.contents buf
;;

let valid_identity text =
  (not (String.is_empty text))
  && String.length text <= max_identity_bytes
  && String.equal text (sanitize ~max:max_identity_bytes text)
;;

module Wire = struct
  let atom text = Sexp.Atom text
  let list values = Sexp.List values
  let record fields = list (List.map fields ~f:(fun (key, value) -> list [ atom key; value ]))

  exception Invalid of string

  let invalid text = raise (Invalid text)

  let values = function
    | Sexp.List values -> values
    | Sexp.Atom _ -> invalid "Expected a Silver list"
  ;;

  let text = function
    | Sexp.Atom text -> text
    | Sexp.List _ -> invalid "Expected a Silver atom"
  ;;

  let identity sexp =
    let text = text sexp in
    if not (valid_identity text) then invalid "Invalid Silver identity";
    text
  ;;

  let find field sexp =
    List.fold (values sexp) ~init:None ~f:(fun found -> function
      | Sexp.List [ Sexp.Atom key; value ] when String.equal key field ->
        if Option.is_some found then invalid ("Duplicate Silver field: " ^ field);
        Some value
      | _ -> found)
  ;;

  let field sexp key =
    match find key sexp with
    | Some value -> value
    | None -> invalid ("Missing Silver field: " ^ key)
  ;;

  let option = function
    | Sexp.List [] -> None
    | Sexp.List [ value ] -> Some value
    | _ -> invalid "Invalid Silver option"
  ;;

  let decode body f =
    if String.length body > Silver_http.max_body_bytes
    then Error "Silver HTTP body exceeds the size limit"
    else (
      try Ok (f (Sexp.of_string body)) with
      | Invalid text -> Error text
      | _ -> Error "Malformed Silver S-expression")
  ;;

  let rpc_error sexp =
    let kind = field sexp "kind" |> text |> sanitize ~max:max_label_bytes in
    let message = field sexp "message" |> text |> sanitize ~max:max_label_bytes in
    invalid (kind ^ ": " ^ message)
  ;;

  let result f = function
    | Sexp.List [ Sexp.Atom "Ok"; payload ] -> f payload
    | Sexp.List [ Sexp.Atom "Error"; payload ] -> rpc_error payload
    | _ -> invalid "Invalid Silver RPC result"
  ;;

  let hello sexp =
    if not (List.exists (field sexp "protocol_versions" |> values) ~f:(Sexp.equal (atom "1")))
    then invalid "Silver daemon does not support protocol v1";
    if not (List.exists (field sexp "capabilities" |> values) ~f:(Sexp.equal (atom "simulation")))
    then invalid "Silver daemon does not support simulation observation";
    field sexp "instance_id" |> identity
  ;;

  let opened ~project_root = result (fun payload ->
    let project = field payload "project" in
    let root = field (field project "root") "path" |> identity in
    if not (String.equal root project_root)
    then invalid "Silver opened a different project root (use its canonical absolute path)";
    field project "id" |> identity)
  ;;

  let lifecycle sexp =
    match text sexp with
    | ("Queued" | "Running" | "Finished" | "Cancelled" | "Interrupted") as value -> value
    | _ -> invalid "Unknown Silver simulation lifecycle"
  ;;

  let outcome sexp =
    match text sexp with
    | "Unknown" -> None
    | ("Passed" | "Failed" | "Incomplete") as value -> Some value
    | _ -> invalid "Unknown Silver simulation outcome"
  ;;

  let attempt sexp ~selection =
    { id = field sexp "id" |> identity
    ; suite = field selection "suite" |> text |> sanitize ~max:max_label_bytes
    ; lifecycle = field sexp "lifecycle" |> lifecycle
    ; outcome = field sexp "outcome" |> outcome
    }
  ;;

  let snapshot ~binding ~instance_id ~project_id = result (fun payload ->
    let attempts, truncated =
      match binding.run with
      | None ->
        let rows = field payload "attempts" |> values in
        let truncated =
          List.length rows > max_status_rows
          || Option.exists (find "next_before" payload) ~f:(fun page -> Option.is_some (option page))
        in
        List.map (List.take rows max_status_rows) ~f:(fun row -> attempt row ~selection:row), truncated
      | Some id ->
        let detail =
          match field payload "detail" |> option with
          | Some detail -> detail
          | None -> invalid "Silver did not return the requested attempt"
        in
        let root = field detail "project_root" |> identity in
        if not (String.equal root binding.project_root)
        then invalid "Silver attempt belongs to a different project";
        let row = attempt detail ~selection:(field (field detail "captured") "selection") in
        if not (String.equal row.id id) then invalid "Silver returned a different attempt";
        [ row ], false
    in
    { binding; instance_id; project_id; attempts; truncated })
  ;;

  let hello_request = { meth = `Get; path = "/api/hello"; headers = []; body = "" }

  let post ~path fields =
    { meth = `Post
    ; path
    ; headers = [ "Content-Type", "application/sexp"; "X-Workbench-Protocol", "1" ]
    ; body = record fields |> Sexp.to_string_mach
    }
  ;;

  let open_project_request ~instance_id ~project_root =
    post ~path:"/api/v1/open-project"
      [ "instance_id", atom instance_id; "root", atom project_root; "environment", atom "Inherit_daemon" ]
  ;;

  let status_request ~instance_id ~project_id ~run =
    let operation =
      match run with
      | None -> atom "Get"
      | Some run -> list [ atom "Observe"; atom run ]
    in
    post ~path:"/api/v1/simulation"
      [ "instance_id", atom instance_id; "project", atom project_id; "operation", operation ]
  ;;
end

type session =
  { binding : binding
  (* Identity of this binding's lifetime, not just equality of its values. *)
  ; stop : unit Ivar.t
  ; mutable request_stop : unit Ivar.t option
  }

type t =
  { peer : peer
  ; timeout : Time_ns.Span.t
  ; poll_interval : Time_ns.Span.t
  ; retry_initial : Time_ns.Span.t
  ; retry_max : Time_ns.Span.t
  ; mutable disposed : bool
  ; mutable session : session option
  ; mutable availability : availability
  ; mutable revision : int
  ; mutable changed : unit Ivar.t
  }

let create
  ?(peer = http_peer)
  ?(timeout = Time_ns.Span.of_int_sec 5)
  ?(poll_interval = Time_ns.Span.of_int_sec 1)
  ?(retry_initial = Time_ns.Span.of_int_ms 250)
  ?(retry_max = Time_ns.Span.of_int_sec 5)
  ()
  =
  List.iter [ timeout; poll_interval; retry_initial; retry_max ] ~f:(fun span ->
    if Time_ns.Span.(span <= zero) then invalid_arg "Silver time intervals must be positive");
  if Time_ns.Span.(retry_max < retry_initial)
  then invalid_arg "Silver retry_max must not be smaller than retry_initial";
  { peer; timeout; poll_interval; retry_initial; retry_max; disposed = false; session = None
  ; availability = Unavailable "No Silver binding"; revision = 0; changed = Ivar.create ()
  }
;;

let latest t = t.availability
let revision t = t.revision
let await_change t ~after = if t.revision <> after then Deferred.unit else Ivar.read t.changed

let publish ?(force = false) t value =
  if force || not (Poly.equal t.availability value)
  then (
    t.availability <- value;
    t.revision <- t.revision + 1;
    Ivar.fill_if_empty t.changed ();
    t.changed <- Ivar.create ())
;;

let active session = not (Ivar.is_full session.stop)

let previous t =
  match t.availability with
  | Unavailable _ -> None
  | Fresh snapshot | Stale (snapshot, _) -> Some snapshot
;;

let read t (session : session) request decode =
  if not (active session)
  then return (Error "Silver binding closed")
  else (
    let stop = Ivar.create () in
    session.request_stop <- Some stop;
    let peer =
      Monitor.try_with ~rest:(`Call ignore) (fun () ->
        t.peer ~endpoint:session.binding.endpoint ~timeout:t.timeout ~stop:(Ivar.read stop) request)
    in
    let%map result =
      Clock_ns.with_timeout t.timeout
        (Deferred.choose
           [ Deferred.choice (Ivar.read session.stop) (fun () -> Error "Silver binding closed")
           ; Deferred.choice peer (function Ok response -> response | Error _ -> Error "Silver transport failed")
           ])
    in
    (match result with
     | `Timeout -> Ivar.fill_if_empty stop ()
     | `Result _ -> ());
    session.request_stop <- None;
    if not (active session)
    then Error "Silver binding closed"
    else
      let decoded =
        match result with
        | `Timeout -> Error "Silver request timed out"
        | `Result (Error reason) -> Error reason
        | `Result (Ok { status = 200; body }) -> Wire.decode body decode
        | `Result (Ok { status; body }) ->
          let reason = Wire.decode body Wire.rpc_error in
          let reason = match reason with Error text -> text | Ok _ -> assert false in
          Error (Printf.sprintf "Silver HTTP %d: %s" status reason)
      in
      Result.map_error decoded ~f:(sanitize ~max:max_label_bytes))
;;

let connect t (session : session) =
  let project_root = session.binding.project_root in
  match%bind read t session Wire.hello_request Wire.hello with
  | Error reason -> return (Error reason)
  | Ok instance_id ->
    if active session && Option.exists (previous t) ~f:(fun old ->
      not (String.equal old.instance_id instance_id))
    then publish t (Unavailable "Silver daemon instance changed; reopening project");
    let%map result =
      read t session (Wire.open_project_request ~instance_id ~project_root) (Wire.opened ~project_root)
    in
    Result.map result ~f:(fun project_id ->
      if active session && Option.exists (previous t) ~f:(fun old ->
        not (String.equal old.project_id project_id))
      then publish t (Unavailable "Silver project session changed; reading status");
      instance_id, project_id)
;;

let rec loop t (session : session) ~connection ~backoff =
  if not (active session)
  then Deferred.unit
  else (
    let binding = session.binding in
    let%bind connection =
      match connection with Some ids -> return (Ok ids) | None -> connect t session
    in
    let%bind result =
      match connection with
      | Error reason -> return (Error reason)
      | Ok (instance_id, project_id) ->
        read t session (Wire.status_request ~instance_id ~project_id ~run:binding.run)
          (Wire.snapshot ~binding ~instance_id ~project_id)
    in
    if not (active session)
    then Deferred.unit
    else (
      let wait, connection, backoff =
        match result with
        | Ok snapshot ->
          publish t (Fresh snapshot);
          t.poll_interval, Result.ok connection, t.retry_initial
        | Error reason ->
          publish t
            (match previous t with
             | None -> Unavailable reason
             | Some latest -> Stale (latest, reason));
          let next =
            if Time_ns.Span.(backoff >= t.retry_max - backoff)
            then t.retry_max
            else Time_ns.Span.(backoff + backoff)
          in
          backoff, None, next
      in
      let%bind () =
        Deferred.any_unit [ Ivar.read session.stop; Clock_ns.after wait ]
      in
      loop t session ~connection ~backoff))
;;

let release t =
  Option.iter t.session ~f:(fun session ->
    Ivar.fill_if_empty session.stop ();
    Option.iter session.request_stop ~f:(fun stop -> Ivar.fill_if_empty stop ()));
  t.session <- None
;;

let rebind t binding =
  if not t.disposed
  then (
    release t;
    if not (valid_identity binding.endpoint)
    then publish ~force:true t (Unavailable "Invalid explicit Silver endpoint")
    else if not (valid_identity binding.project_root) || Filename.is_relative binding.project_root
    then publish ~force:true t (Unavailable "Silver project root must be an absolute canonical path")
    else if Option.exists binding.run ~f:(fun run -> not (valid_identity run))
    then publish ~force:true t (Unavailable "Invalid Silver attempt ID")
    else (
      let session = { binding; stop = Ivar.create (); request_stop = None } in
      t.session <- Some session;
      publish ~force:true t (Unavailable "Connecting to Silver");
      upon Deferred.unit (fun () ->
        don't_wait_for (loop t session ~connection:None ~backoff:t.retry_initial))))
;;

let unbind t =
  if not t.disposed
  then (
    release t;
    publish t (Unavailable "No Silver binding"))
;;

let shutdown t =
  if not t.disposed
  then (
    t.disposed <- true;
    release t;
    publish t (Unavailable "Silver observation stopped"))
;;
