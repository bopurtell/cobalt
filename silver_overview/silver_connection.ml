open! Core
open! Async

type source =
  | Advertised
  | Known
  | Explicit

type candidate =
  { endpoint : string
  ; source : source
  ; instance_id : string option
  }

let endpoint t = t.endpoint
let source t = t.source

type lookup =
  { candidates : candidate list
  ; advertisement_error : string option
  }

module Metadata = struct
  type t =
    { endpoint : string
    ; instance_id : string
    ; pid : int
    }
  [@@deriving of_sexp]
end

let candidate source ?instance_id text =
  Result.map (Silver_http.normalize_endpoint (String.strip text)) ~f:(fun endpoint ->
    { endpoint; source; instance_id })
;;

let explicit text = candidate Explicit text

let native_directory () =
  let nonempty_env name =
    Option.filter (Sys.getenv name) ~f:(Fn.non String.is_empty)
  in
  let root =
    match nonempty_env "XDG_RUNTIME_DIR" with
    | Some root -> root
    | None ->
      Option.value_or_thunk (nonempty_env "XDG_STATE_HOME") ~default:(fun () ->
        Filename.concat (Sys_unix.home_directory ()) ".local/state")
  in
  Filename.concat root "hardcaml-workbench"
;;

exception Invalid_advertisement

let max_metadata_bytes = 8192

let read_file path =
  let before = Core_unix.lstat path in
  let valid (st : Core_unix.stats) =
    Poly.equal st.st_kind Core_unix.S_REG
    && st.st_uid = Core_unix.geteuid ()
    && st.st_perm land 0o022 = 0
    && Int64.(st.st_size <= of_int max_metadata_bytes)
  in
  if not (valid before) then raise Invalid_advertisement;
  let fd = Core_unix.openfile path ~mode:[ O_RDONLY; O_CLOEXEC; O_NONBLOCK ] in
  Exn.protect ~finally:(fun () -> Core_unix.close fd) ~f:(fun () ->
    let after = Core_unix.fstat fd in
    if not (valid after) || before.st_dev <> after.st_dev || before.st_ino <> after.st_ino
    then raise Invalid_advertisement;
    let buf = Bytes.create (max_metadata_bytes + 1) in
    let rec read pos =
      if pos > max_metadata_bytes then raise Invalid_advertisement;
      let n = Core_unix.read ~restart:true ~pos ~len:(Bytes.length buf - pos) fd ~buf in
      if n = 0 then Stdlib.Bytes.sub_string buf 0 pos else read (pos + n)
    in
    read 0)
;;

let read_advertisement directory =
  try
    let directory = Option.value_or_thunk directory ~default:native_directory in
    let body = read_file (Filename.concat directory "daemon.sexp") in
    let ({ endpoint; instance_id; pid } : Metadata.t) = Sexp.of_string body |> Metadata.t_of_sexp in
    if pid <= 0
       || String.is_empty instance_id
       || String.length instance_id > 4096
       || String.exists instance_id ~f:(fun c -> Char.to_int c < 32 || Char.equal c '\127')
    then raise Invalid_advertisement;
    (match candidate Advertised ~instance_id endpoint with
     | Ok advertised -> Ok (Some advertised)
     | Error reason -> Error ("Invalid Silver daemon advertisement: " ^ reason))
  with
  | Core_unix.Unix_error (Core_unix.ENOENT, _, _) -> Ok None
  | Core_unix.Unix_error _ -> Error "Cannot read Silver daemon advertisement"
  | _ -> Error "Invalid Silver daemon advertisement"
;;

let lookup ?directory ?(known = []) () =
  let%map advertisement = In_thread.run (fun () -> read_advertisement directory) in
  let advertised, advertisement_error =
    match advertisement with
    | Ok advertised -> Option.to_list advertised, None
    | Error error -> [], Some error
  in
  let known = List.filter_map known ~f:(fun text -> candidate Known text |> Result.ok) in
  let _, choices =
    List.fold (advertised @ known) ~init:(Set.empty (module String), []) ~f:(fun (seen, acc) c ->
      let key =
        match String.chop_prefix c.endpoint ~prefix:"http://localhost:" with
        | None -> c.endpoint
        | Some port -> "http://127.0.0.1:" ^ port
      in
      if Set.mem seen key then seen, acc else Set.add seen key, c :: acc)
  in
  { candidates = List.rev choices; advertisement_error }
;;

let connect ?peer ?timeout { endpoint; instance_id; _ } ~project_root =
  Silver_overview.Testing.connect
    ?peer ?timeout ?expected_instance_id:instance_id ~endpoint ~project_root ()
;;
