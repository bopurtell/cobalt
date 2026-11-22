open! Core

let source = "blues"
let prog = "blues"
let args = [ "lsp" ]
let language_id _ = "bsv"
let root_markers = [ "blues.toml"; "blues_compdb.json" ]
let resolve_program () = Option.value (Sys.getenv "BLUES_LSP") ~default:prog

let applies_to path =
  match snd (Filename.split_extension path) with
  | Some "bsv" ->
    (try
       let root = Workspace_root.find_nearest ~markers:root_markers path in
       List.exists root_markers ~f:(fun name -> Sys_unix.is_file_exn (Filename.concat root name))
     with
     | _ -> false)
  | _ -> false
;;
