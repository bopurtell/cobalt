open! Core
open Cobalt_highlight
open Cobalt_highlight_tree_sitter

let%test_unit "C++ DPI wrapper highlights linkage, includes and calls across edits" =
  let provider = Provider.create ~language:Cpp in
  let document = Snapshot.Document_id.create () in
  let source = {|#include "svdpi.h"
#include <cstdint>
// DPI entry point
extern "C" int dpi_tick(const svBitVecVal *input) {
  return bridge::step(input[0]);
}
|} in
  List.iteri [ "step"; "advance" ] ~f:(fun revision call ->
    let source = String.substr_replace_first source ~pattern:"step" ~with_:call in
    let key = Provider.key provider ~document ~revision in
    let result = Provider.highlight_incremental provider ~key ~source in
    if not (Provider.Status.equal result.status (Highlighted { syntax_errors = false }))
    then raise_s [%sexp "unexpected DPI highlight status", (result.status : Provider.Status.t)];
    List.iter
      [ "#include", Category.Keyword; "\"svdpi.h\"", String; "<cstdint>", String
      ; "// DPI entry point", Comment; "extern", Keyword; "\"C\"", String
      ; "dpi_tick", Function; "svBitVecVal", Type; "bridge", Module; call, Function
      ; "return", Keyword; "0", Number
      ] ~f:(fun (token, category) ->
        let start = String.substr_index_exn source ~pattern:token in
        for i = start to start + String.length token - 1 do
          [%test_result: Category.t] (Snapshot.category_at result.snapshot i) ~expect:category
        done));
  Provider.close provider
;;
