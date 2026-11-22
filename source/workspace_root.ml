open! Core

let find_first ~markers path =
  let directory = Filename.dirname path in
  match Filename_unix.realpath directory with
  | exception _ -> directory
  | start ->
    let rec up marker dir =
      if Sys_unix.file_exists_exn (Filename.concat dir marker)
      then Some dir
      else (
        let parent = Filename.dirname dir in
        if String.equal parent dir then None else up marker parent)
    in
    Option.value (List.find_map markers ~f:(fun marker -> up marker start)) ~default:start
;;

let find = find_first ~markers:[ "dune-project" ]

let find_nearest ~markers path =
  let directory = Filename.dirname path in
  let start = try Filename_unix.realpath directory with _ -> directory in
  let rec up dir =
    if List.exists markers ~f:(fun marker -> Sys_unix.file_exists_exn (Filename.concat dir marker))
    then dir
    else let parent = Filename.dirname dir in
      if String.equal parent dir then start else up parent
  in
  up start
;;

let cargo_manifest path =
  let cwd = Core_unix.getcwd () in
  let directory = Filename.dirname (Cobalt_core.Resource.normalize ~cwd path) in
  let rec up dir =
    let manifest = Filename.concat dir "Cargo.toml" in
    let parent = Filename.dirname dir in
    match Sys_unix.is_file manifest with
    | `Yes -> Some manifest
    | `No | `Unknown -> if String.equal parent dir then None else up parent
  in
  let directory = try Filename_unix.realpath directory with _ -> directory in
  up directory
;;

let cargo_workspace manifest =
  let open Async in
  let working_dir = Filename.dirname manifest in
  (* No build, dependency resolution or lockfile generation. In particular, don't
     reproduce Cargo's TOML/workspace membership rules with a marker heuristic. *)
  match%bind Process.create ~prog:"cargo" ~working_dir
    ~args:[ "locate-project"; "--workspace"; "--frozen"; "--manifest-path"; manifest ] () with
  | Error _ -> return None
  | Ok process ->
    let output = Process.collect_output_and_wait process in
    (match%bind Clock_ns.with_timeout (Time_ns.Span.of_int_sec 3) output with
     | `Timeout ->
       ignore (Process.send_signal_compat process Signal.kill : [ `Ok | `No_such_process ]);
       Process.wait process >>| fun _ -> None
     | `Result { exit_status = Error _; _ } -> return None
     | `Result { stdout; exit_status = Ok (); _ } ->
       return (match Yojson.Safe.from_string stdout with
         | `Assoc [ "root", `String path ]
           when not (Filename.is_relative path) && String.equal (Filename.basename path) "Cargo.toml" ->
           Some (Filename.dirname path)
         | _ | exception _ -> None))
;;
