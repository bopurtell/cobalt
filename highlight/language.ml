open! Core

type t = Plain | Ocaml | Ocaml_interface | Systemverilog | Gas | Rust | Bsv | Classic | Cpp
[@@deriving sexp_of, equal]

let of_path = function
  | Some path when String.is_suffix path ~suffix:".mli" -> Ocaml_interface
  | Some path when String.is_suffix path ~suffix:".ml" -> Ocaml
  | Some path when String.is_suffix path ~suffix:".rs" -> Rust
  | Some path
    when List.exists [ ".cc"; ".cpp"; ".cxx"; ".hh"; ".hpp"; ".hxx"; ".C" ]
           ~f:(fun suffix -> String.is_suffix path ~suffix) -> Cpp
  | Some path when String.is_suffix path ~suffix:".bsv" -> Bsv
  | Some path when String.is_suffix path ~suffix:".bs" -> Classic
  | Some path when String.is_suffix path ~suffix:".s" || String.is_suffix path ~suffix:".S" -> Gas
  | Some path
    when List.exists [ ".sv"; ".svh"; ".v"; ".vh" ] ~f:(fun suffix ->
      String.is_suffix path ~suffix) -> Systemverilog
  | Some _ | None -> Plain
;;
