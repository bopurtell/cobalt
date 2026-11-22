open! Core
open Cobalt_screen

let parse text = Sexp.of_string text |> Hosted_layout.t_of_sexp
let width = 120
let height = 36
let workspace t = Ui_state.workspace t ~width ~height
let run t keys = Helpers.run ~width ~height t (Helpers.keys keys)

let create ?layout () =
  let controller = Ui_state.controller (Helpers.ui ~path:"a.txt" "source text") in
  Ui_state.create ?layout controller
;;

let%test_unit "the hosted layout codec validates the workspace's constraints" =
  let layout = parse
    "((views ((History Band) (Problems Band) (Language_servers Tab) (Vcs Split))) \
     (status ((position Above) (size 5))) (split ((view_side Left) (percent 40))))" in
  assert (Hosted_layout.equal layout (Hosted_layout.t_of_sexp (Hosted_layout.sexp_of_t layout)));
  List.iter
    [ "((views ((Problems Band) (Problems Hidden))))"
    ; "((views ((Problems Split) (History Split))))"
    ; "((views ((Unknown Band))))"
    ; "((views ((Problems Bottom))))"
    ; "((status ((position Below) (size 0))))"
    ; "((split ((view_side Left) (percent 81))))"
    ]
    ~f:(fun text ->
      match Or_error.try_with (fun () -> parse text) with
      | Error _ -> ()
      | Ok _ -> failwith ("Unexpectedly accepted hosted layout: " ^ text))
;;

let%test_unit "Problems fills the bottom band without default History or Status" =
  let default = workspace (create ()) in
  assert (Option.is_some default.status);
  assert (Option.is_none (Workspace.minor default History_tile.id));
  let t = create ~layout:(parse "((views ((Problems Band))))") () in
  let w = workspace t in
  let problems = Workspace.minor w Problems_tile.id |> Option.value_exn in
  assert (Option.is_none w.status);
  assert (Option.is_none (Workspace.minor w History_tile.id));
  assert (w.document.rect.width = width);
  assert (problems.rect.x = 0 && problems.rect.width = width);
  assert (w.document.rect.height = problems.rect.y);
  assert (problems.rect.y + problems.rect.height = height);
  let zen = run t " vz" in
  assert (List.is_empty (workspace zen).minors);
  assert (Workspace.equal (workspace (run zen " vz")) w);
  let bare = run t " vB" in
  assert (List.is_empty (workspace bare).minors);
  assert (Workspace.equal (workspace (run bare " vB")) w);
  let toggled = workspace (run t " vm vt") in
  assert (Option.is_some (Workspace.minor toggled History_tile.id));
  assert (Option.is_some toggled.status)
;;

let%test_unit "ordered bands, inactive tabs, sized split and relocated Status share the existing allocator" =
  let layout = parse
    "((views ((History Band) (Problems Band) (Language_servers Tab) (Vcs Split))) \
     (status ((position Above) (size 5))) (split ((view_side Left) (percent 40))))" in
  let vcs = Vcs_view.entry ~cwd:"/" () in
  let controller = Ui_state.controller (Helpers.ui ~path:"a.txt" "source text") in
  let t = Ui_state.create ~layout ~views:[ vcs ] controller in
  let w = workspace t in
  let rect id = (Option.value_exn (Workspace.minor w id)).rect in
  let status = Option.value_exn w.status in
  assert (status.rect.y = 0 && status.rect.height = 5);
  assert ((rect History_tile.id).x < (rect Problems_tile.id).x);
  assert ((rect Vcs_view.id).x < w.document.rect.x);
  assert ((rect Vcs_view.id).width = (width - Workspace.gap) * 40 / 100);
  assert (Option.is_none (Ui_state.active_tab_view t));
  assert (List.exists (Ui_state.tab_items t) ~f:(fun item ->
    String.equal item.label "Language servers" && not item.active));
  let compact = Ui_state.workspace t ~width:24 ~height:4 in
  assert (Option.is_none (Workspace.minor compact Vcs_view.id));
  assert (Workspace.equal (workspace t) w)
;;
