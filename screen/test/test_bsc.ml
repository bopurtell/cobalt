open! Core
open Cobalt_core
open Cobalt_screen
module Feedback = Cobalt_error.Error
module Bsc = Cobalt_app.Bsc
module Controller = Cobalt_app.Controller

let width = 120
let height = 30
let run t keys = Helpers.run ~width ~height t (Helpers.keys keys)
let feedback t = Ui_state.controller t |> Controller.feedback
let editor t = Ui_state.controller t |> Controller.editor
let collections t = Feedback.diagnostics (feedback t) |> Feedback.Diagnostics.collections
let sources t = List.map (collections t) ~f:(fun c -> c.source)
let find ~root file text = Filename.concat root file, text

let%test_unit "BSC grammar preserves diagnostics, including the code and multiline text" =
  let output = {|checking package dependencies
Error: "pkg space/Classic.bs", line 3, column 17: (T0004)
  Unbound variable `woops'
  Some extra explanation.
Warning: "/other/Some\"file.bsv", line 5: (P0001)
  A warning.
Error: Command line: (S0008)
  Missing search path.
ignoring non-BSC command output
|} in
  match Bsc.findings ~root:"/project" output with
  | [ p1, { severity = Error; message; location = Some { line = 3; column = 17 } }
    ; p2, { severity = Warning; location = Some { line = 5; column = 1 }; _ }
    ; p3, { severity = Error; location = None; message = message3 } ] ->
    assert (String.equal p1 "/project/pkg space/Classic.bs");
    assert (String.equal message "(T0004) Unbound variable `woops' Some extra explanation.");
    assert (String.equal p2 "/other/Some\"file.bsv");
    assert (String.equal p3 "/project/.cobalt-bsc");
    assert (String.equal message3 "Command line: (S0008) Missing search path.")
  | _ -> assert false
;;

let%test_unit "project check and build accept literal argv and reject malformed configuration" =
  let text = {|((check (bsc -u -p "+:lib name" "source/top.bsv"))
                 (build ("./script with space" "x; $y")))|} in
  let { Bsc.program; args } = Bsc.command Check text |> Or_error.ok_exn in
  assert (String.equal program "bsc" && [%equal: string list] args [ "-u"; "-p"; "+:lib name"; "source/top.bsv" ]);
  let { Bsc.program; args } = Bsc.command Build text |> Or_error.ok_exn in
  assert (String.equal program "./script with space" && [%equal: string list] args [ "x; $y" ]);
  List.iter [ "((build (make)))"; "((check ()))"; "((check (a)) (check (b)))";
    "((check (bsc (bad))))"; "((third (bsc)))"; "(" ]
    ~f:(fun text -> assert (Result.is_error (Bsc.command Check text)))
;;

let%test_unit "BSC run identity, clickable mixed-language locations, and stale-result isolation" =
  let root = Helpers.scratch_dir "cobalt-bsc-test" in
  let first, text1 = find ~root "A.bsv" "package A;\n  badToken;\nendpackage\n" in
  let second, text2 = find ~root "B.bs" "package B where\n\t界badToken\n" in
  Exn.protect ~finally:(fun () ->
    List.iter [first; second] ~f:(fun path -> if Stdlib.Sys.file_exists path then Core_unix.unlink path);
    Core_unix.rmdir root) ~f:(fun () ->
    Out_channel.write_all first ~data:text1;
    Out_channel.write_all second ~data:text2;
    let t = Helpers.ui ~path:first text1 in
    assert (Option.is_none (snd (Ui_state.take_bsc_request t)));
    let other = { Feedback.Diagnostics.Finding.severity = Info; message = "other source"; location = None } in
    let t = Ui_state.update_feedback t ~width ~height
      (Diagnostics_received { source = "other"; resource = first;
        findings = [ other ]; revision = None; current_revision = 0 }) in
    let start t command =
      let t = run t (" cc" ^ command ^ "<CR>") in
      let t, request = Ui_state.take_bsc_request t in
      t, Option.value_exn request in
    let t, first_run = start t "bsc check" in
    assert (first_run.id = 1 && Bsc.equal_action first_run.action Check);
    assert (String.equal first_run.directory root && List.is_empty first_run.dirty);
    let finding line column =
      { Feedback.Diagnostics.Finding.severity = Error; message = "broken"; location = Some { line; column } } in
    let failed = { Bsc.root; findings = [ first, finding 2 3; second, finding 2 9 ]; success = false; status = "Failed" } in
    let t = Ui_state.receive_bsc t ~width ~height first_run failed in
    assert ([%equal: string list] (sources t) [ "BSC run #1"; "other"; "BSC run #1" ]);
    let t = run t " vogg<CR>" in
    assert (Editor.cursor (editor t) = Text_buffer.line_start (Editor.text (editor t)) 1 + 2);
    let t = run t " voG<CR>" in
    assert ([%equal: string option] (Editor.path (editor t)) (Some second));
    assert (Editor.cursor (editor t) = Text_buffer.line_start (Editor.text (editor t)) 1 + 4);
    let t, second_run = start t "bsc build" in
    assert (second_run.id = 2 && Bsc.equal_action second_run.action Build);
    assert ([%equal: string list] (sources t) [ "other" ]);
    let t = Ui_state.receive_bsc t ~width ~height first_run failed in
    assert ([%equal: string list] (sources t) [ "other" ]);
    let t = run t "iUNSAVED<Esc>" in
    let t = Ui_state.receive_bsc t ~width ~height second_run failed in
    assert ([%equal: string list] (sources t) [ "other" ]);
    assert (Editor.is_dirty (editor t));
    assert (String.equal (In_channel.read_all second) text2);
    let t = run t "u" in
    let t, third_run = start t "bsc check" in
    assert (List.is_empty third_run.dirty);
    let t = Ui_state.receive_bsc t ~width ~height third_run failed in
    assert (List.mem (sources t) "BSC run #3" ~equal:String.equal);
    let t = run t "iEDIT<Esc>" in
    if not ([%equal: string list] (sources t) [ "other" ])
    then failwith (String.concat ~sep:", " (sources t));
    let t, fourth_run = start (run t "u") "bsc check" in
    let t = Ui_state.receive_bsc t ~width ~height fourth_run
      { root; findings = []; success = true; status = "Succeeded: 0 findings" } in
    assert ([%equal: string list] (sources t) [ "other" ]))
;;
