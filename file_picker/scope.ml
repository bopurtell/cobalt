open! Core

(* Shared default ripgrep policy: no hidden files or symlink following,
   no config injection, and an explicit metadata exclusion. File discovery can
   opt out of ignores without changing content search's default policy. *)
let rg_args = [ "--no-config"; "--glob"; "!**/.git/**" ]
let file_rg_args ~include_ignored =
  rg_args @ (if include_ignored then [ "--no-ignore" ] else [])
;;
let visible_path path =
  not (List.exists (String.split path ~on:'/') ~f:(String.is_prefix ~prefix:"."))
;;
