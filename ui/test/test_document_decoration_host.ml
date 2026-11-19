open! Core
open Cobalt_core
open Cobalt_screen
open Cobalt_ui

module Host = Document_decoration_host
module Snapshot = Cobalt_decoration.Snapshot

let text source =
  Text_buffer.of_string source
  |> Result.map_error ~f:Text_buffer.Invalid_text.to_string_hum
  |> Result.ok_or_failwith
;;

let ui ?(path = "fixture.md") source =
  Cobalt_app.Controller.create (Editor.create ~path ~cell_width:Cell_map.width (text source))
  |> Ui_state.create ~bare:true
;;

let enable ui = Ui_state.with_document_decorations ~enabled:true ui ~available:true
let disable ui = Ui_state.with_document_decorations ~enabled:false ui ~available:true
let keys string = List.map (String.to_list string)
  ~f:(fun char -> Ui_state.Input.Key (Cobalt_input.Key.char char))
let apply ui inputs = fst (Ui_state.apply_all ui ~width:80 ~height:24 inputs)

type fixture =
  { host : Host.t
  ; factory : Host.Factory.t
  ; creates : int ref
  ; parses : int ref
  ; closes : int ref
  ; failure : bool ref
  ; stale : bool ref
  ; configuration : string ref
  }

let fixture () =
  let creates = ref 0 and parses = ref 0 and closes = ref 0 in
  let failure = ref false and stale = ref false and configuration = ref "v1" in
  let factory : Host.Factory.t =
    { available = true
    ; eligible_path = (function Some path -> String.is_suffix path ~suffix:".md" | None -> false)
    ; create = (fun () ->
        incr creates;
        { Host.Session.key = (fun ~document ~revision ->
            Snapshot.Key.create ~document ~revision ~provider:"synthetic"
              ~configuration:!configuration)
        ; close = (fun () -> incr closes)
        ; decorate = (fun ~key ~source ->
            incr parses;
            if !failure then Or_error.error_string "synthetic failure"
            else
              let key = if !stale then
                  Snapshot.Key.create ~document:(Snapshot.Document_id.create ())
                    ~revision:(Snapshot.Key.revision key) ~provider:"wrong" ~configuration:"wrong"
                else key in
              let operations = if String.length source < 2 then [] else
                [ Snapshot.Operation.Style
                    { range = { start = 0; stop = 1 }; role = Accent } ] in
              Snapshot.create ~key ~source operations)
        })
    } in
  { host = Host.create factory; factory; creates; parses; closes; failure; stale; configuration }
;;

let present fixture ui = Option.is_some (Host.decorations fixture.host ui)

let%test_unit "off, unsupported, unnamed and over-budget inputs never create a session" =
  let f = fixture () in
  ignore (Host.follow f.host (ui "anchor\nbody") : Ui_state.t);
  ignore (Host.follow f.host (enable (ui ~path:"fixture.txt" "anchor\nbody")) : Ui_state.t);
  ignore (Host.follow f.host (enable (ui (String.make (256 * 1024 + 1) 'x'))) : Ui_state.t);
  ignore (Host.follow f.host (enable (ui (String.make 4097 '\n'))) : Ui_state.t);
  let unnamed = Cobalt_app.Controller.create
    (Editor.create ~cell_width:Cell_map.width (text "unnamed"))
    |> Ui_state.create |> enable in
  ignore (Host.follow f.host unnamed : Ui_state.t);
  assert (!(f.creates) = 0 && !(f.parses) = 0 && !(f.closes) = 0)
;;

let%test_unit "movement, dimensions, theme and drawing never parse; configuration does" =
  let f = fixture () in
  let ui = Host.follow f.host (enable (ui "anchor\nbody\nlast")) in
  assert (present f ui && !(f.parses) = 1);
  let moved = apply ui (keys "ljk") in
  let resized = fst (Ui_state.apply_all moved ~width:100 ~height:30 [ Resize ]) in
  let themed = apply resized (keys " vTglacier" @ [ Key Escape ]) in
  let themed = Host.follow f.host themed in
  let first = Option.value_exn (Host.decorations f.host themed) in
  for _ = 1 to 20 do
    let next = Host.follow f.host themed in
    let _, prepared = Option.value_exn (Host.decorations f.host next) in
    assert (phys_equal prepared (snd first));
    ignore (Frame.render ~decorations:first next ~width:100 ~height:30 : Frame.t)
  done;
  assert (!(f.creates) = 1 && !(f.parses) = 1);
  f.configuration := "v2";
  let changed = Host.follow f.host themed in
  assert (present f changed && !(f.parses) = 2);
  Host.clear f.host;
  Host.clear f.host;
  assert (!(f.closes) = 1)
;;

let%test_unit "batched edits clear old payload per step, parse once, then undo and redo refresh" =
  let f = fixture () in
  let original = Host.follow f.host (enable (ui "anchor\nbody")) in
  let edited = apply original (keys "iABC" @ [ Key Escape ]) in
  assert (not (present f edited));
  let stale_cleared = ref false in
  let after_step model =
    let model = Host.follow ~parse:false f.host model in
    if not (phys_equal (Editor.text (Cobalt_app.Controller.editor (Ui_state.controller model)))
              (Editor.text (Cobalt_app.Controller.editor (Ui_state.controller original))))
    then stale_cleared := not (present f model);
    model in
  let edited = fst (Ui_state.apply_all ~after_step original ~width:80 ~height:24
    (keys "iABC" @ [ Key Escape ])) |> Host.follow f.host in
  assert (!stale_cleared && present f edited && !(f.parses) = 2);
  let undone = apply edited (keys "u") in
  assert (not (present f undone));
  let undone = Host.follow f.host undone in
  assert (present f undone && !(f.parses) = 3);
  let redone = apply undone [ Key (Cobalt_input.Key.Ctrl 'r') ]
    |> Host.follow f.host in
  assert (present f redone && !(f.parses) = 4 && !(f.creates) = 1);
  let disabled = Host.follow f.host (disable redone) in
  assert (not (present f disabled) && !(f.closes) = 1);
  let enabled = Host.follow f.host (enable disabled) in
  assert (present f enabled && !(f.creates) = 2 && !(f.parses) = 5);
  Host.clear f.host
;;

let%test_unit "provider errors and stale keys clear data, close, and notify once per source" =
  List.iter [ false; true ] ~f:(fun stale ->
    let f = fixture () in
    let initial = Host.follow f.host (enable (ui "anchor\nbody")) in
    f.failure := not stale;
    f.stale := stale;
    let edited = apply initial (keys "x") |> Host.follow f.host in
    assert (not (present f edited) && !(f.closes) = 1 && !(f.parses) = 2);
    let feedback = Ui_state.capture_notice edited in
    assert (Option.exists feedback ~f:(fun notice ->
      String.is_prefix notice ~prefix:"Document decorations failed:"));
    for _ = 1 to 20 do
      ignore (Host.follow f.host (apply edited (keys "l")) : Ui_state.t)
    done;
    assert (!(f.creates) = 1 && !(f.parses) = 2 && !(f.closes) = 1);
    f.failure := false;
    f.stale := false;
    let recovered = apply edited (keys "x") |> Host.follow f.host in
    assert (present f recovered && !(f.creates) = 2 && !(f.parses) = 3);
    Host.clear f.host)
;;

let%test_unit "buffer switches, path changes and reload identities release the prior owner" =
  let f = fixture () in
  let initial = Host.follow f.host (enable (ui "anchor\nbody")) in
  let controller = Ui_state.controller initial in
  let renamed = Cobalt_app.Controller.reassociate controller "renamed.md"
    |> Ui_state.create ~bare:true |> enable in
  assert (not (present f renamed));
  let renamed = Host.follow f.host renamed in
  assert (present f renamed && !(f.creates) = 2 && !(f.closes) = 1);
  (* A replacement controller has a new runtime identity even at revision zero
     and with exactly equal text; neither source keys nor native state may leak. *)
  let reloaded = enable (ui ~path:"renamed.md" "anchor\nbody")
    |> Host.follow f.host in
  assert (present f reloaded && !(f.creates) = 3 && !(f.closes) = 2);
  let switched = enable (ui ~path:"second.md" "second\nbody")
    |> Host.follow f.host in
  assert (present f switched && !(f.creates) = 4 && !(f.closes) = 3);
  let exited = apply switched (keys " Q") in
  ignore (Host.follow f.host exited : Ui_state.t);
  assert (not (present f exited) && !(f.closes) = 4)
;;

let%test_unit "real session tab activation releases and recreates only the active provider" =
  let f = fixture () in
  let first = Host.follow f.host (enable (ui "anchor\nbody")) in
  let first_id = Option.value_exn (Cobalt_app.Session.active_id (Ui_state.session first)) in
  let second, second_id = Ui_state.open_file first ~width:80 ~height:24
    "__cobalt_host_second_unwritten__.md" |> Or_error.ok_exn in
  assert (not (present f second));
  let second = Host.follow f.host second in
  assert (present f second && !(f.creates) = 2 && !(f.closes) = 1);
  let first = Ui_state.activate_buffer second ~width:80 ~height:24 first_id
    |> Or_error.ok_exn |> Host.follow f.host in
  assert (present f first && !(f.creates) = 3 && !(f.parses) = 3 && !(f.closes) = 2);
  let second = Ui_state.activate_buffer first ~width:80 ~height:24 second_id
    |> Or_error.ok_exn |> Host.follow f.host in
  assert (present f second && !(f.creates) = 4 && !(f.parses) = 4 && !(f.closes) = 3);
  Host.clear f.host;
  Cobalt_app.Session.dispose (Ui_state.session second)
;;

let%test_unit "major directories and view-only tabs never parse hidden retained files" =
  let f = fixture () in
  let initial = Ui_state.create (Ui_state.controller (ui "anchor\nbody")) |> enable in
  let directory = Ui_state.show_directory initial ~width:160 ~height:50 "."
    |> Or_error.ok_exn |> Host.follow ~width:160 ~height:50 f.host in
  assert (!(f.creates) = 0 && not (present f directory));
  let sidebar = fst (Ui_state.apply_all directory ~width:160 ~height:50 (keys " ds"))
    |> Host.follow ~width:160 ~height:50 f.host in
  assert (Option.is_some (Ui_state.side_layout sidebar ~width:160 ~height:50));
  assert (!(f.creates) = 1 && !(f.parses) = 1);
  assert (Option.is_some (Host.decorations ~width:160 ~height:50 f.host sidebar));
  let major = fst (Ui_state.apply_all sidebar ~width:160 ~height:50 (keys " dm"))
    |> Host.follow ~width:160 ~height:50 f.host in
  assert (!(f.closes) = 1 && !(f.parses) = 1);
  assert (Option.is_none (Host.decorations ~width:160 ~height:50 f.host major));
  Host.clear f.host;
  let f = fixture () in
  let view = apply initial (keys " vo ccMove focused view to a tab" @ [ Key Enter ]) in
  assert (Option.is_some (Ui_state.active_tab_view view));
  ignore (Host.follow f.host view : Ui_state.t);
  assert (!(f.creates) = 0 && !(f.parses) = 0)
;;

let%expect_test "production host starts after configuration; redraws and palette toggles use the same lifecycle" =
  let f = fixture () in
  let controller = Ui_state.controller (ui "anchor\nbody") in
  let handle = Bonsai_term_test.create_handle
    (Editor_view.app ~document_decorations:f.factory ~document_decorations_enabled:true
      ~startup_configuration:(Ok Cobalt_config_runtime.Settings.default) ~bare:true
      controller ~exit:(fun () -> Bonsai_term.Effect.Ignore)) in
  let recompute () =
    for _ = 1 to 3 do Bonsai_test.Handle.recompute_view handle done in
  Bonsai_term_test.set_dimensions handle { width = 100; height = 30 };
  recompute ();
  assert (!(f.creates) = 1 && !(f.parses) = 1);
  let chars string = List.iter (String.to_list string) ~f:(fun char ->
    Bonsai_term_test.send_event handle (Key_press { key = ASCII char; mods = [] })) in
  chars "lj";
  Bonsai_term_test.set_dimensions handle { width = 110; height = 32 };
  for _ = 1 to 20 do recompute () done;
  assert (!(f.parses) = 1);
  chars "x";
  recompute ();
  assert (!(f.parses) = 2);
  let toggle () =
    chars " ccToggle document decorations";
    Bonsai_term_test.send_event handle (Key_press { key = Enter; mods = [] });
    recompute () in
  toggle ();
  assert (!(f.closes) = 1 && !(f.parses) = 2);
  toggle ();
  assert (!(f.creates) = 2 && !(f.parses) = 3);
  chars " Q";
  recompute ();
  assert (!(f.closes) = 2);
  ignore ([%expect.output] : string);
  print_endline "startup opt-in; movement/resize/redraw no parse; edit refresh; palette off/on; shutdown closes";
  [%expect {| startup opt-in; movement/resize/redraw no parse; edit refresh; palette off/on; shutdown closes |}]
;;

let%test_unit "unavailable composition emits one bounded notice and remains an editing UI" =
  let host = Host.create Host.Factory.unavailable in
  let initial = enable (ui "anchor\nbody") |> Host.follow host in
  assert (not (Ui_state.document_decorations_available initial));
  assert (Option.value_map (Ui_state.capture_notice initial) ~default:false
    ~f:(String.equal "Document decorations unavailable in this build"));
  let changed = apply initial (keys "x") |> Host.follow host in
  assert (not (String.equal
    (Text_buffer.to_string (Editor.text (Cobalt_app.Controller.editor (Ui_state.controller changed))))
    "anchor\nbody"));
  assert (Option.is_none (Host.decorations host changed));
  let acknowledged = apply changed [ Key Escape ] |> Host.follow host in
  let notices model =
    Cobalt_app.Controller.feedback (Ui_state.controller model)
    |> Cobalt_error.Error.history |> Cobalt_error.Error.History.entries
    |> List.filter_map ~f:(fun entry -> match entry.event with
      | Notified notice when String.equal notice.source "document decorations" ->
        Some entry.count
      | _ -> None) in
  assert ([%equal: int list] (notices initial) [ 1 ]);
  assert ([%equal: int list] (notices acknowledged) [ 1 ]);
  for _ = 1 to 20 do
    let next = Host.follow host acknowledged in
    assert ([%equal: int list] (notices next) [ 1 ])
  done
;;

let%test_unit "configuration application preserves both enabled and disabled session choices" =
  let f = fixture () in
  let initial = enable (ui "anchor\nbody") |> Host.follow f.host in
  let configured = Ui_state.apply_configuration initial Cobalt_config_runtime.Settings.default
    |> Result.ok_or_failwith |> Host.follow f.host in
  assert (Ui_state.document_decorations_enabled configured && !(f.parses) = 1);
  let disabled = disable configured |> Host.follow f.host in
  let configured = Ui_state.apply_configuration disabled Cobalt_config_runtime.Settings.default
    |> Result.ok_or_failwith |> Host.follow f.host in
  assert (not (Ui_state.document_decorations_enabled configured) && !(f.parses) = 1);
  assert (Ui_state.document_decorations_available configured)
;;

type callback_site = Create | Key | Decorate | Close [@@deriving equal]

exception Unexpected_callback_failure

let callback_fixture () =
  let fault = ref None in
  let calls = ref 0 in
  let invoke site =
    incr calls;
    Option.iter !fault ~f:(fun (expected, raise_) ->
      if equal_callback_site site expected then raise_ ()) in
  let factory : Host.Factory.t =
    { available = true
    ; eligible_path = (fun _ -> true)
    ; create = (fun () ->
        invoke Create;
        { Host.Session.key = (fun ~document ~revision ->
            invoke Key;
            Snapshot.Key.create ~document ~revision ~provider:"exceptions"
              ~configuration:"v1")
        ; decorate = (fun ~key ~source ->
            invoke Decorate;
            Snapshot.create ~key ~source [])
        ; close = (fun () -> invoke Close)
        })
    } in
  Host.create factory, fault, calls
;;

let%test_unit "fatal, interrupt and unrelated callback exceptions propagate unchanged" =
  let cases =
    [ `Memory, (fun () -> raise Out_of_memory)
    ; `Stack, (fun () -> raise Stack_overflow)
    ; `Break, (fun () -> raise Stdlib.Sys.Break)
    ; `Unexpected, (fun () -> raise Unexpected_callback_failure)
    ] in
  List.iter cases ~f:(fun (expected, raise_) ->
    List.iter [ Create; Key; Decorate; Close ] ~f:(fun site ->
      let host, fault, _ = callback_fixture () in
      let model = enable (ui "anchor\nbody") in
      let model = if equal_callback_site site Close then Host.follow host model else model in
      fault := Some (site, raise_);
      let actual =
        try
          if equal_callback_site site Close then Host.clear host
          else ignore (Host.follow host model : Ui_state.t);
          None
        with
        | Out_of_memory -> Some `Memory
        | Stack_overflow -> Some `Stack
        | Stdlib.Sys.Break -> Some `Break
        | Unexpected_callback_failure -> Some `Unexpected in
      assert (Option.equal Poly.equal actual (Some expected));
      fault := None;
      Host.clear host))
;;

let%test_unit "recoverable callback exceptions clear payloads, notify once and latch the failed source" =
  List.iter
    [ (fun () -> failwith "expected callback failure")
    ; (fun () -> invalid_arg "expected callback argument failure") ]
    ~f:(fun raise_ ->
      List.iter [ Create; Key; Decorate ] ~f:(fun site ->
        let host, fault, calls = callback_fixture () in
        let initial = enable (ui "anchor\nbody") in
        let initial = if equal_callback_site site Create then initial
          else Host.follow host initial in
        fault := Some (site, raise_);
        let edited = apply initial (keys "x") |> Host.follow host in
        assert (Option.is_none (Host.decorations host edited));
        assert (Option.exists (Ui_state.capture_notice edited) ~f:(fun notice ->
          String.is_prefix notice ~prefix:"Document decorations failed:"));
        let baseline = !calls in
        for _ = 1 to 20 do
          ignore (Host.follow host edited : Ui_state.t)
        done;
        assert (!calls = baseline);
        fault := None;
        let recovered = apply edited (keys "x") |> Host.follow host in
        assert (Option.is_some (Host.decorations host recovered));
        Host.clear host);
      let host, fault, _ = callback_fixture () in
      let model = enable (ui "anchor\nbody") |> Host.follow host in
      fault := Some (Close, raise_);
      Host.clear host;
      assert (Option.is_none (Host.decorations host model)))
;;
