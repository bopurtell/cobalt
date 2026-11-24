open! Core
open Cobalt_screen
module B = Cobalt_vcs_git.Backend
module Diff = Cobalt_vcs.Diff
module Fixture = Cobalt_vcs_fixture.Fixture_repo
module Job = Cobalt_vcs.Job
module Text_view = Cobalt_tile.Text_view

let width = 100
let height = 24
let lines = String.concat (List.init 200 ~f:(sprintf "large patch line %d\n"))
let state t = View_registry.find (Ui_state.views t) Vcs_view.key |> Option.value_exn
let text_view t = Vcs_view.text_view (state t) |> Option.value_exn
let keys t keys = Helpers.run ~width ~height t (Helpers.keys keys)
let settle repo t = fst (Vcs_driver.settle repo t ~width ~height)

let with_staged_files f =
  Fixture.with_repo (fun repo ->
    Fixture.write repo "a.txt" "a\n";
    Fixture.write repo "b.txt" "b\n";
    Fixture.write repo "large.txt" "large\n";
    ignore (Fixture.commit_all repo "first" : string);
    Fixture.write repo "a.txt" "new a\n";
    Fixture.write repo "b.txt" "new b\n";
    Fixture.write repo "large.txt" lines;
    ignore (Fixture.git repo [ "add"; "." ] : string);
    let controller =
      Cobalt_app.Controller.open_file
        ~cell_width:Cell_map.width
        (Fixture.path repo "large.txt")
      |> Or_error.ok_exn
    in
    let t =
      Ui_state.create
        ~tiles_visible:false
        ~views:[ Vcs_view.entry ~cwd:repo.work () ]
        controller
    in
    (* Explicitly select the header, independent of the initial selection policy. *)
    f repo (settle repo (keys (settle repo (keys t " gg")) "gg")))
;;

let take_job t ~lane =
  let t, jobs = Ui_state.take_vcs_jobs t in
  match jobs with
  | [ (job : Job.t) ] when Option.equal String.equal job.lane (Some lane) -> t, job
  | jobs ->
    raise_s
      [%message
        "Unexpected VCS jobs" (List.map jobs ~f:Vcs_driver.describe : string list)]
;;

let finish repo t job =
  Helpers.run
    ~width
    ~height
    t
    (List.map (Vcs_driver.events repo job) ~f:(fun event -> Ui_state.Input.Vcs event))
;;

let loading t target =
  match Vcs_view.diff (state t) with
  | Loading actual ->
    [%test_result: bool] (B.equal_diff_target actual target) ~expect:true
  | actual ->
    raise_s [%message "Expected a loading diff" (actual : Vcs_view.Diff_state.t)]
;;

let loaded_files t target =
  match Vcs_view.diff (state t) with
  | Loaded (actual, diff) ->
    [%test_result: bool] (B.equal_diff_target actual target) ~expect:true;
    List.map diff.files ~f:Diff.File.path
  | actual -> raise_s [%message "Expected a loaded diff" (actual : Vcs_view.Diff_state.t)]
;;

let frame t ~width = Frame.to_string (Frame.render t ~width ~height)
let contains text substring = String.is_substring text ~substring

let%test_unit "delayed target reports cannot replace the loading row or the newer patch" =
  with_staged_files (fun repo t ->
    [%test_result: string list]
      (loaded_files t (Staged []))
      ~expect:[ "a.txt"; "b.txt"; "large.txt" ];
    let t, a = take_job (keys t "j") ~lane:"diff" in
    loading t (Staged [ "a.txt" ]);
    let for_a = frame t ~width:91 in
    assert (contains for_a "Staged: a.txt (loading)");
    assert (contains for_a "Loading diff...");
    assert (not (contains for_a "diff --git"));
    let t, b = take_job (keys t "j<Tab>") ~lane:"diff" in
    (* The loading view has no aggregate text to lay out, even at a new width. *)
    let check_loading t =
      loading t (Staged [ "b.txt" ]);
      [%test_result: string] (Text_view.text (text_view t)) ~expect:"Loading diff...";
      let for_b = frame t ~width:83 in
      assert (contains for_b "Staged: b.txt (loading)");
      assert (not (contains for_b "diff --git"))
    in
    check_loading t;
    (* Check both arrival orders from the same pending state. *)
    check_loading (finish repo t a);
    let t = finish repo t b in
    [%test_result: string list] (loaded_files t (Staged [ "b.txt" ])) ~expect:[ "b.txt" ];
    let t = finish repo t a in
    [%test_result: string list] (loaded_files t (Staged [ "b.txt" ])) ~expect:[ "b.txt" ];
    let rendered = frame t ~width in
    assert (contains rendered "diff --git a/b.txt b/b.txt");
    assert (not (contains rendered "diff --git a/a.txt")))
;;

let%test_unit "loading a different target cannot act on the preceding patch" =
  with_staged_files (fun _ t ->
    let t, _ = take_job (keys t "j<Tab>") ~lane:"diff" in
    let t = keys t "v" in
    [%test_result: bool] (Option.is_none (Text_view.visual (text_view t))) ~expect:true;
    let t = keys t "yy" in
    let t, clipboard = Ui_state.take_clipboard t in
    [%test_result: string option] clipboard ~expect:None;
    let t =
      List.fold [ "]"; "}"; "{" ] ~init:t ~f:(fun t key ->
        let t = keys t key in
        [%test_result: int] (Text_view.cursor (text_view t)) ~expect:0;
        t)
    in
    let t = keys t "e<CR>usx" in
    [%test_result: bool]
      (Cobalt_tile.View_id.equal (Ui_state.focused_view t ~width ~height) Vcs_view.id)
      ~expect:true;
    [%test_result: string option]
      (Ui_state.capture_notice t)
      ~expect:(Some "The diff is still loading");
    let _, jobs = Ui_state.take_vcs_jobs t in
    assert (List.is_empty jobs))
;;

let%test_unit "a pending result cannot return after switching to a row with no diff" =
  with_staged_files (fun repo t ->
    let t, a = take_job (keys t "j") ~lane:"diff" in
    let t = finish repo (keys t "2") a in
    match Vcs_view.diff (state t) with
    | No_diff -> ()
    | actual -> raise_s [%message "Expected no diff" (actual : Vcs_view.Diff_state.t)])
;;

let%test_unit "refreshing the same target keeps the diff cursor and scroll position" =
  with_staged_files (fun repo t ->
    let t = keys (settle repo (keys t "G<Tab>")) "60G4l" in
    let view = text_view t in
    let cursor = Text_view.cursor view in
    let top = Text_view.top view in
    let original = Text_view.text view in
    assert (cursor > 0 && top > 0);
    let check_position t =
      let view = text_view t in
      [%test_result: int] (Text_view.cursor view) ~expect:cursor;
      [%test_result: int] (Text_view.top view) ~expect:top
    in
    Fixture.write repo "large.txt" (lines ^ "another staged line\n");
    ignore (Fixture.git repo [ "add"; "large.txt" ] : string);
    let t, refresh = take_job (keys t "gr") ~lane:"refresh" in
    let t, diff = take_job (finish repo t refresh) ~lane:"diff" in
    loading t (Staged [ "large.txt" ]);
    check_position t;
    let t = finish repo t diff in
    [%test_result: string list]
      (loaded_files t (Staged [ "large.txt" ]))
      ~expect:[ "large.txt" ];
    assert (not (String.equal original (Text_view.text (text_view t))));
    check_position t)
;;
