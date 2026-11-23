open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Cobalt_screen

let draw_span ?theme ?font ({ text; width; style } : Frame.Span.t) =
  let attrs = Theme.attrs ?theme ?font style in
  let view = View.text ~attrs text in
  let drawn = View.width view in
  if drawn = width
  then view
  else if drawn > width
  then View.crop ~r:(drawn - width) view
  else View.hcat [ view; View.rectangle ~attrs ~width:(width - drawn) ~height:1 () ]
;;

let draw_smear ?theme ?font (frame : Frame.t) =
  let cells = List.sort frame.smear ~compare:(fun (x1, y1) (x2, y2) -> [%compare: int * int] (y1, x1) (y2, x2)) in
  match cells with
  | [] -> View.none
  | _ ->
    let rows = List.group cells ~break:(fun (_, y1) (_, y2) -> y1 <> y2) in
    let first_y = snd (List.hd_exn cells) in
    let row_view cells =
      let rec loop previous_x = function
        | [] -> []
        | (x, _) :: rest ->
          let gap = Int.max 0 (x - previous_x) in
          View.transparent_rectangle ~width:gap ~height:1
          :: View.text ~attrs:(Theme.attrs ?theme ?font Smear) "█"
          :: loop (x + 1) rest
      in
      View.hcat (loop 0 cells)
    in
    View.vcat
      (View.transparent_rectangle ~width:0 ~height:first_y
       :: List.concat_mapi rows ~f:(fun i row ->
         let y = snd (List.hd_exn row) in
         let previous_y = if i = 0 then first_y else snd (List.hd_exn (List.nth_exn rows (i - 1))) in
         View.transparent_rectangle ~width:0 ~height:(Int.max 0 (y - previous_y - 1)) :: [ row_view row ]))
;;

let draw_base ?theme ?font (frame : Frame.t) =
  View.vcat
    (List.map frame.rows ~f:(fun spans ->
       View.hcat (List.map spans ~f:(draw_span ?theme ?font))))
;;

let draw_overlay ?theme ?font ~base frame =
  View.zcat [ draw_smear ?theme ?font frame; base ]
;;

let draw ?theme ?font frame =
  draw_overlay ?theme ?font ~base:(draw_base ?theme ?font frame) frame
;;

let cursor (frame : Frame.t) : Cursor.t option =
  Option.map frame.cursor ~f:(fun { x; y; shape } ->
    { Cursor.position = { x; y }
    ; kind =
        (match shape with
         | Block -> Block
         | Bar -> Bar)
    })
;;

let fit_view view ~width ~height =
  let columns = View.width view and rows = View.height view in
  if columns = width && rows = height then view
  else
    View.crop ~r:(Int.max 0 (columns - width)) ~b:(Int.max 0 (rows - height)) view
    |> View.pad ~r:(Int.max 0 (width - columns)) ~b:(Int.max 0 (height - rows))
;;

module File_picker_host = struct
  type t =
    { initial_ui : Ui_state.t
    ; runtime : Cobalt_file_picker_host.Runtime.t
    ; consume : Cobalt_tile.View_id.t Cobalt_file_picker.Model.Request.t -> unit
    }
end

module Content_picker_host = struct
  type t =
    { initial_ui : Ui_state.t
    ; runtime : Cobalt_content_picker_host.Runtime.t
    ; consume : Cobalt_tile.View_id.t Cobalt_content_picker.Model.intent -> unit
    }
end

let apply_startup_configuration ?theme_override ~configure_layout ui result =
  let apply settings =
    Result.map (Ui_state.apply_configuration ?theme_override ui settings)
      ~f:(configure_layout settings) in
  match Result.bind result ~f:apply with
  | Ok ui -> ui
  | Error error ->
    let ui = match apply Cobalt_config_runtime.Settings.default with
      | Ok ui -> ui
      | Error _ -> ui in
    Ui_state.with_notice ~source:"configuration" ui
      ("Configuration startup failed; using defaults: " ^ error)
;;

type hosted =
  { view : View.t
  ; cursor : Cursor.t option
  ; handle_event : Event.t -> unit Effect.t
  ; open_location : Cobalt_app.Session.Open_location.request
      -> (Cobalt_app.Buffer_id.t, [ `Closed | `Open of Cobalt_app.Session.Open_location.failure ]) Result.t Effect.t
  ; shutdown : unit -> unit Effect.t
  ; closed : bool
  }

module Open_location = Cobalt_app.Session.Open_location

type open_location_listener =
  project_root:string
  -> on_request:(Open_location.request -> (unit, Open_location.failure) Result.t Async.Deferred.t)
  -> (unit -> unit Async.Deferred.t) Async.Deferred.Or_error.t

let component ?layout ?terminal ?snippets ?configuration ?startup_configuration ?configuration_path ?document_decorations ?document_decoration_host ?(document_decorations_enabled = false) ?(smear_enabled = false) ?mouse ?(zen = false) ?bare ?theme ?appearance ?buffer_presentation ?report ?(silver_overview : Silver_overview_host.t option) ?(force_startup_silver_overview = false) ?source ?vcs ?font ?file_picker ?content_picker ?on_toggle_terminal ?host_commands ?on_host_command ?on_open_location_ready ?(hosted_silver_navigation = false) ?(standalone_layouts = false) ~set_clipboard controller ~exit ~blank_on_close ~dimensions ~visible ~focused (local_ graph)
  =
  let dimensions = let%arr { Dimensions.width; height } = dimensions in
    { Dimensions.width = Int.max 0 width; height = Int.max 0 height } in
  let accepts_input = let%arr visible and focused and { Dimensions.width; height } = dimensions in
    visible && focused && width > 0 && height > 0 in
  (* Scope belongs to this editor instance, not the currently active tab. Directory
     startup and unnamed documents use the session's explicit startup directory. *)
  let production_runtime = Cobalt_file_picker_host.Runtime.create () in
  let harness = Harness_host.create () in
  let bsc = Bsc_host.create () in
  let content_runtime = Option.value_map content_picker
    ~default:(Cobalt_content_picker_host.Runtime.create ())
    ~f:(fun host -> host.Content_picker_host.runtime) in
  let starting_directory = match Cobalt_core.Editor.path (Cobalt_app.Controller.editor controller) with
    | None -> Core_unix.getcwd ()
    | Some path -> if Cobalt_app.Controller.Kind.equal (Cobalt_app.Controller.kind controller) Directory
      then path else Filename.dirname path in
  let project_root = Cobalt_file_discovery.Project_root.find
    (Filename.concat starting_directory "__picker_scope__") in
  let file_runtime = Option.value_map file_picker ~default:production_runtime
    ~f:(fun host -> host.File_picker_host.runtime) in
  (* The VCS view looks for a repository from the startup directory. Without a
     runner it is known only by id, so Space g reports why nothing opens. *)
  let vcs_entry = match vcs with
    | Some _ ->
      let cwd = if Filename.is_relative starting_directory
        then Filename.concat (Core_unix.getcwd ()) starting_directory
        else starting_directory in
      Vcs_view.entry ~cwd ()
    | None ->
      View_registry.Entry.unavailable Vcs_view.id ~title:"VCS"
        ~notice:"VCS unavailable in this session" in
  let initial_ui = match content_picker, file_picker with
    | Some _, Some _ -> invalid_arg "Only one initial picker host is allowed"
    | Some host, None -> host.Content_picker_host.initial_ui
    | None, Some host -> host.File_picker_host.initial_ui
    | None, None ->
       Ui_state.create ?layout ~standalone_layouts
         ~smear_enabled ?bare ?theme ?buffer_presentation ?report
        ~source_attached:(Option.is_some source)
        ~views:
           [ Silver_overview_host.entry silver_overview
           ; Silver_overview_host.stage_entry silver_overview
          ; Silver_kickoff_host.entry (Option.bind silver_overview ~f:(fun host -> host.kickoff))
          ; Silver_kickoff_host.review_entry (Option.bind silver_overview ~f:(fun host -> host.kickoff))
          ; vcs_entry
           ] controller in
  let configuration_path = Option.value_or_thunk configuration_path ~default:(fun () ->
    match Cobalt_config_runtime.Loader.config_path ~getenv:Sys.getenv with
    | Some path -> Ok path
    | None -> Error "Cannot locate configuration: set an absolute XDG_CONFIG_HOME or a non-empty HOME") in
  let initial_ui = Ui_state.with_configuration_path initial_ui configuration_path in
  let initial_ui =
    match silver_overview with
    | None -> Ui_state.with_silver_test initial_ui (Unavailable "Silver adapter is not available in this session")
    | Some host ->
      Silver_overview_host.synchronize initial_ui host |> Ui_state.with_silver_connection ~project_root
  in
  let configure_layout (settings : Cobalt_config_runtime.Settings.t) ui =
    match content_picker, file_picker with
    | Some _, _ | _, Some _ -> ui
    | None, None ->
      let ui =
        if standalone_layouts && not (force_startup_silver_overview || settings.startup_silver_overview)
        then Ui_state.hide_initial_silver_overview ui
        else ui in
      (* Enter Zen via the usual transition. Bare keeps its Workspace return target. *)
      if zen && not (Ui_state.bare ui || (standalone_layouts && settings.startup_workspace))
      then fst (Ui_state.apply_all ui ~width:0 ~height:0
        (List.map (String.to_list " vz") ~f:(fun c ->
           Ui_state.Input.Key (Cobalt_input.Key.char c))))
      else ui in
  let initial_ui = match startup_configuration with
    | None -> configure_layout Cobalt_config_runtime.Settings.default initial_ui
    | Some result ->
      apply_startup_configuration ?theme_override:theme ~configure_layout initial_ui result in
  let initial_ui = if Option.is_some appearance
    then Ui_state.with_external_appearance initial_ui else initial_ui in
  let appearance = match appearance with
    | None -> Bonsai.return None
    | Some appearance -> let%arr appearance in Some appearance in
  (* Session opt-in is applied after configuration; providers are injected only
     by executable composition. Neither screen rendering nor config loads them. *)
  let document_decorations = Option.value_or_thunk document_decoration_host ~default:(fun () ->
    Document_decoration_host.create
      (Option.value document_decorations ~default:Document_decoration_host.Factory.unavailable)) in
  let initial_ui = Ui_state.with_document_decorations
    ~enabled:document_decorations_enabled initial_ui ~available:false
    |> Document_decoration_host.follow ~parse:false document_decorations in
  let initial_ui = if Option.is_some on_toggle_terminal
    then Ui_state.with_external_terminal initial_ui else initial_ui in
  let initial_ui = Option.value_map mouse ~default:initial_ui
    ~f:(fun enabled -> Ui_state.with_mouse_reporting initial_ui ~enabled) in
  let initial_ui = if hosted_silver_navigation
    then Ui_state.with_hosted_silver_navigation initial_ui else initial_ui in
  let on_toggle_terminal =
    Option.value on_toggle_terminal ~default:(Bonsai.return (fun _ -> Effect.Ignore)) in
  let host_commands, on_host_command =
    match host_commands, on_host_command with
    | Some commands, Some dispatch -> commands, dispatch
    | _ -> Bonsai.return [], Bonsai.return (fun _ -> Effect.Ignore)
  in
  let current_ui = ref initial_ui in
  let navigation_preview = Navigation_preview_host.create ~buffer:(fun request ->
    Ui_state.navigation_preview_buffer !current_ui request) () in
  let navigation_preview_pumping = ref false in
  let synchronize_navigation_preview model =
    current_ui := model;
    Navigation_preview_host.follow navigation_preview
      (if Ui_state.exited model then None else Ui_state.navigation_preview_request model);
    model in
  let configuration = Option.value_or_thunk configuration ~default:(fun () -> Configuration_host.create ()) in
  let snippets = Option.value_or_thunk snippets ~default:Snippet_host.create in
  let word_index = Word_index_host.create () in
  let render_cache = Frame.Cache.create () in
  let last_drawn_theme = ref None in
  let synchronized_dimensions = ref None in
  let preview = Cobalt_file_preview.Provider.create ~buffer:(fun ~path ->
    Cobalt_file_preview.Buffer_snapshot.lookup (Ui_state.session !current_ui) ~path) () in
  let preview_pumping = ref false in
  let preview_revision = ref None in
  let clear_preview () =
    Frame.Cache.invalidate render_cache;
    preview_revision := None;
    Cobalt_file_preview.Provider.clear preview;
    Option.iter (Ui_state.file_picker !current_ui) ~f:File_picker_tile.clear_preview in
  let synchronize_preview model =
    (* Replacements must release the old screen payload as well as provider work. *)
    let old_picker = Ui_state.file_picker !current_ui in
    let picker = if Ui_state.exited model then None else Ui_state.file_picker model in
    if not (Option.equal phys_equal old_picker picker) then (
      clear_preview ());
    current_ui := model;
    let selected_model = Option.map picker ~f:(fun picker ->
      Cobalt_file_picker.Interaction.model (File_picker_tile.session picker)) in
    let expected = Cobalt_file_preview.Provider.follow preview selected_model in
    let revision = Option.bind expected ~f:(fun request ->
      Option.bind (Cobalt_app.Session.find_resource (Ui_state.session model)
        (Cobalt_file_picker.Model.Candidate.Id.to_string request.selected))
        ~f:(fun (id, controller) -> match Cobalt_app.Controller.kind controller with
          | Directory -> None
          | File -> Some (id, Cobalt_core.Editor.revision (Cobalt_app.Controller.editor controller)))) in
    let refresh = match !preview_revision, expected with
      | Some (previous, old_revision), Some expected ->
        Cobalt_file_preview.Model.equal_request previous expected
        && not (Option.equal
          (fun (id, revision) (other_id, other_revision) ->
            Cobalt_app.Buffer_id.equal id other_id && revision = other_revision)
          old_revision revision)
      | _ -> false in
    let expected = if refresh then Cobalt_file_preview.Provider.follow ~refresh:true preview selected_model
      else expected in
    preview_revision := Option.map expected ~f:(fun expected -> expected, revision);
    Option.iter picker ~f:(fun picker ->
      File_picker_tile.expect_preview picker expected;
      Option.iter (Cobalt_file_preview.Provider.snapshot preview) ~f:(fun snapshot ->
        ignore (File_picker_tile.install_preview picker snapshot : bool)));
    model in
  let picker_turn_scheduled = ref false in
  let active_file_session = ref (Option.bind file_picker ~f:(fun host ->
    Option.map (Ui_state.file_picker host.File_picker_host.initial_ui)
      ~f:File_picker_tile.session)) in
  let active_line_session = ref None in
  let active_content_session = ref (Option.bind content_picker ~f:(fun host ->
    Option.map (Ui_state.content_picker host.Content_picker_host.initial_ui)
      ~f:Content_picker_tile.session)) in
  let stopping = Async.Ivar.create () in
  let finished = Async.Ivar.create () in
  let silver_open = ref false in
  let silver_stage_open = ref false in
  let stopped () = Async.Ivar.is_full stopping in
  let stop () =
    if not (stopped ()) then (
      Async.Ivar.fill_exn stopping ();
      if not (Ui_state.exited !current_ui)
      then Cobalt_app.Session.dispose (Ui_state.session !current_ui);
      Harness_host.stop harness;
      Bsc_host.stop bsc;
      Navigation_preview_host.stop navigation_preview;
      Document_decoration_host.clear document_decorations;
      Word_index_host.stop word_index;
      Snippet_host.stop snippets;
      Option.iter silver_overview ~f:(fun host -> host.shutdown ());
      Option.iter source ~f:Cobalt_source.Source.stop;
      Option.iter !active_file_session ~f:(fun session ->
        Cobalt_file_picker.Interaction.cancel session ~release:(fun () -> ()));
      Option.iter !active_content_session ~f:(fun session ->
        Cobalt_content_picker.Model.cancel session ~release:(fun () -> ()));
      Option.iter !active_line_session ~f:(fun session ->
        Cobalt_line_picker.Lines.cancel session ~release:(fun () -> ()));
      clear_preview ();
      Cobalt_file_picker_host.Runtime.cancel file_runtime;
      Cobalt_content_picker_host.Runtime.cancel content_runtime;
      let waits =
         [ Configuration_host.shutdown configuration
         ; Cobalt_file_picker_host.Runtime.finished file_runtime
         ; Cobalt_content_picker_host.Runtime.finished content_runtime
         ] in
       let waits = match terminal with
         | None -> waits
         | Some host -> Terminal_host.shutdown host :: waits in
      let waits = match vcs with
        | None -> waits
        | Some host -> Async.Deferred.ignore_m (Vcs_host.shutdown host) :: waits in
      Async.upon (Async.Deferred.all_unit waits) (fun () -> Async.Ivar.fill_exn finished ()))
  in
  let until_stopping next =
    if stopped () then Async.return None
    else
      Async.Deferred.choose
        [ Async.Deferred.choice (Async.Ivar.read stopping) (fun () -> None)
        ; Async.Deferred.choice (next ()) Option.some
        ]
  in
  let line_needs_turn model =
    not (Ui_state.exited model)
    && Option.exists (Ui_state.line_picker model) ~f:(fun picker ->
      Cobalt_line_picker.Lines.busy (Line_picker_tile.session picker))
  in
  let picker_needs_turn model =
    not (Ui_state.exited model)
    && Option.exists (Ui_state.file_picker model) ~f:(fun picker ->
      let session = File_picker_tile.session picker in
      Cobalt_file_picker.Interaction.busy session
       || match Cobalt_file_picker.Model.discovery_status (Cobalt_file_picker.Interaction.model session) with
         | Loading | Partial -> true
         | Complete _ | Failed _ | Cancelled -> false)
  in
  let cancel_outer_input model =
    let model = Ui_state.cancel_toggle_prefix model in
    let model = Ui_state.cancel_editor_divider_drag model in
    if Ui_state.pasting model then Ui_state.cancel_paste model else model
  in
  let model, inject_action =
    Bonsai.state_machine_with_input
       ~default_model:initial_ui
      ~apply_action:(fun context input model action ->
         let answer reply result = Async.Ivar.fill_if_empty reply result in
         match input, action with
          | _, `Shutdown when stopped () -> model
          | Active ({ Dimensions.width; height }, _, _, _, _, _), `Shutdown ->
           let model, _ = Ui_state.quit_session model ~width ~height ~force:true in
           current_ui := model;
           stop ();
           Frame.Cache.invalidate render_cache;
           model
         | Inactive, `Shutdown -> stop (); model
         | Inactive, `Open_location (_, reply) -> answer reply (Error `Closed); model
         | _, `Open_location (_, reply) when stopped () -> answer reply (Error `Closed); model
         | Inactive, _ -> model
          | _, _ when stopped () -> model
           | Active ({ Dimensions.width; height }, set_clipboard, on_toggle_terminal, host_commands, on_host_command, accepts_input), action ->
               let model = Ui_state.with_host_commands model host_commands in
              let model = match action with
                | `Lost_input -> cancel_outer_input model
                | _ when not accepts_input -> cancel_outer_input model
                | _ -> model in
             let model = match action with
              | `Words (request, words) ->
                Frame.Cache.invalidate render_cache;
                Ui_state.receive_word_index model request words
              | `Snippets (generation, result) ->
                Frame.Cache.invalidate render_cache;
                Ui_state.receive_snippets model ~generation result
               | `Configuration (generation, result) ->
                 Frame.Cache.invalidate render_cache;
                 Ui_state.receive_configuration model ~generation result
               | `Navigation_preview snapshot ->
                 Frame.Cache.invalidate render_cache;
                  Ui_state.receive_navigation_preview model snapshot
                 | `Silver_changed ->
                   (match silver_overview with
                    | Some host ->
                      Frame.Cache.invalidate render_cache;
                      Silver_overview_host.synchronize model host
                    | _ -> model)
                | `Silver_feedback result ->
                  Frame.Cache.invalidate render_cache;
                  Ui_state.with_silver_result model result
                 | `Silver_connections (generation, lookup) ->
                   Frame.Cache.invalidate render_cache;
                   Ui_state.receive_silver_connections model ~generation lookup
                 | `Silver_connect_result (generation, result) ->
                   Frame.Cache.invalidate render_cache;
                   Ui_state.receive_silver_connect_result model ~generation result
               | `Harness (request, result) ->
                 Frame.Cache.invalidate render_cache;
                 Ui_state.receive_harness model ~width ~height ~request result
               | `Bsc (request, result) ->
                 Frame.Cache.invalidate render_cache;
                 Ui_state.receive_bsc model ~width ~height request result
               | `Open_location (request, reply) ->
                 (match Ui_state.open_location model ~width ~height request with
                  | Error failure -> answer reply (Error (`Open failure)); model
                  | Ok (model, id) -> answer reply (Ok id); model)
                | `Shutdown | `Lost_input | `Inputs _ | `Event _ -> model in
            (* Capture belongs to the model at this transition, not the last
               displayed handler: several events can arrive before a redraw. *)
            let inputs = match action with
                  | `Words _ | `Snippets _ | `Configuration _ | `Navigation_preview _ | `Harness _ | `Bsc _
                   | `Silver_changed | `Silver_feedback _ | `Silver_connections _
                   | `Silver_connect_result _
                  | `Shutdown | `Lost_input | `Open_location _ -> []
               | `Inputs inputs -> inputs
               | `Event _ when not accepts_input -> []
               | `Event (event, at) ->
                 let mouse = Option.value (Ui_state.mouse_reporting model) ~default:false in
                 Terminal_input.inputs ~terminal:(Ui_state.terminal_capturing model) ~mouse event
                |> List.map ~f:(function
                  | Ui_state.Input.Key key -> Ui_state.Input.Key_at { key; at }
                  | Ui_state.Input.Terminal_key key -> Ui_state.Input.Terminal_key_at { key; at }
                  | input -> input) in
            (* Pure animation turns retain the base image and skip host effects.
               Timeout ticks can flush input, so always use the full path below. *)
            if not (List.is_empty inputs)
               && List.for_all inputs ~f:(function Ui_state.Input.Animation_tick _ -> true | _ -> false)
               && Option.equal [%equal: int * int] !synchronized_dimensions (Some (width, height))
            then (
              let model, _ = Ui_state.apply_all model ~width ~height inputs in
               let model = synchronize_navigation_preview model in
              model)
            else (
            let inputs = if Option.equal [%equal: int * int]
                !synchronized_dimensions (Some (width, height)) then inputs
              else Ui_state.Input.Resize :: inputs in
            synchronized_dimensions := Some (width, height);
           let was_running = not (Ui_state.exited model) in
           if List.exists inputs ~f:(function Ui_state.Input.Resize -> true | _ -> false)
           then clear_preview ();
           let follow_silver model =
             match silver_overview with
             | None -> model
             | Some host ->
               let shown =
                 not (Ui_state.exited model) && Ui_state.view_visible model Silver_overview_tile.id
               in
                let changed = not (Bool.equal shown !silver_open) in
                silver_open := shown;
                 if changed then (if shown then host.show () else host.hide ());
                 let stage_visible =
                   not (Ui_state.exited model)
                   && Ui_state.view_available model ~width ~height Silver_stage_tile.id
                in
                let stage_changed = not (Bool.equal stage_visible !silver_stage_open) in
                silver_stage_open := stage_visible;
                if stage_changed then host.set_stage_visible stage_visible;
                let model, intents = Silver_overview_host.take_intents model in
                 let model, stage_intents = Silver_overview_host.take_stage_intents model in
                 let model, stage_watches = Silver_overview_host.take_stage_watches model in
                 let model = List.fold stage_watches ~init:model ~f:(fun model watch ->
                   match host.watch_stage watch with
                   | Ok () -> model
                   | Error reason -> Ui_state.with_notice ~source:"Silver" model reason)
                 in
                List.iter stage_intents ~f:(fun intent ->
                  let result = host.launch_stage intent in
                  Bonsai.Apply_action_context.schedule_event context
                    (let%bind.Effect result = Effect.of_deferred_thunk (fun () -> result) in
                     Bonsai.Apply_action_context.inject context (`Silver_feedback result)));
               let model =
                 List.fold intents ~init:model ~f:(fun model intent ->
                   match intent with
                   | Refresh ->
                     if shown then host.refresh ();
                     model
                   | Apply_settings (target, fields) ->
                     let result =
                       Result.map (host.apply_settings target fields) ~f:(fun () ->
                         "Saved test settings · " ^ Silver_overview_tile.Target.name target)
                     in
                     Ui_state.with_silver_result model result
                   | Launch target ->
                     (* Start once, regardless of the tile placement. Capture both
                        the target and its settings before the next key. *)
                     let result = host.launch target in
                     Bonsai.Apply_action_context.schedule_event context
                       (let%bind.Effect result = Effect.of_deferred_thunk (fun () -> result) in
                        Bonsai.Apply_action_context.inject context (`Silver_feedback result));
                     model
                   | Connections generation ->
                     Bonsai.Apply_action_context.schedule_event context
                        (let%bind.Effect lookup =
                           Effect.of_deferred_thunk (fun () -> host.connections ~generation) in
                         Bonsai.Apply_action_context.inject context
                           (`Silver_connections (generation, lookup)));
                      model
                    | Connect { generation; selection } ->
                      let request = host.connect selection in
                      Bonsai.Apply_action_context.schedule_event context
                        (let%bind.Effect result = Effect.of_deferred_thunk (fun () -> request) in
                         match result with
                         | None -> Effect.Ignore
                         | Some result ->
                           Bonsai.Apply_action_context.inject context
                             (`Silver_connect_result (generation, result)));
                     model)
               in
                let model =
                  Option.value_map host.kickoff ~default:model
                     ~f:(Silver_kickoff_host.dispatch model ~stages:host.stages)
                in
                 if changed || stage_changed || not (List.is_empty intents)
                    || not (List.is_empty stage_intents) || not (List.is_empty stage_watches)
               then Silver_overview_host.synchronize model host
               else model
           in
           let after_step model =
             let model = follow_silver model in
            let model, activate_files = Ui_state.take_file_picker_activation model in
            let model = match activate_files with None -> model | Some intent ->
              match Cobalt_file_picker_host.Runtime.open_picker ~split:(Poly.equal intent `Split) file_runtime model
                ~settings:(Ui_state.file_picker_settings model)
                ~root:project_root ~width ~height with
              | Ok model -> model
              | Error error -> Ui_state.with_notice model (Error.to_string_hum error) in
            let model, activate_contents = Ui_state.take_content_picker_activation model in
            let model = if not activate_contents then model else
              match Cobalt_content_picker_host.Runtime.open_picker content_runtime model
                ~root:project_root ~width ~height with
              | Ok model -> model
              | Error error -> Ui_state.with_notice ~source:"content picker" model (Error.to_string_hum error) in
              synchronize_navigation_preview (synchronize_preview model)
              |> Document_decoration_host.follow ~parse:false ~width ~height document_decorations
          in
             let model, status = Frame.Cache.apply_inputs render_cache ~after_step model ~width ~height inputs in
             let model = follow_silver model in
            let model = synchronize_navigation_preview (synchronize_preview model)
              |> Document_decoration_host.follow ~width ~height document_decorations in
            current_ui := model;
            if not !navigation_preview_pumping
               && Option.is_some (Navigation_preview_host.snapshot navigation_preview)
            then (
              navigation_preview_pumping := true;
              let rec pump () =
                let changed = Navigation_preview_host.changed navigation_preview in
                match Navigation_preview_host.snapshot navigation_preview with
                | None -> navigation_preview_pumping := false; Effect.Ignore
                | Some snapshot ->
                  let%bind.Effect () = Bonsai.Apply_action_context.inject context
                    (`Navigation_preview snapshot) in
                  let%bind.Effect () = Effect.of_deferred_thunk (fun () -> changed) in
                  pump () in
              Bonsai.Apply_action_context.schedule_event context (pump ()));
           if not !preview_pumping && Option.is_some (Cobalt_file_preview.Provider.snapshot preview)
           then (
             preview_pumping := true;
             let rec pump () =
               (* Capture BEFORE snapshot/injection: injection yields and may itself
                  change selection. Notifications retain no queued payloads. *)
               let changed = Cobalt_file_preview.Provider.changed preview in
               match Cobalt_file_preview.Provider.snapshot preview with
               | None -> preview_pumping := false; Effect.Ignore
               | Some snapshot ->
                 let%bind.Effect () = Bonsai.Apply_action_context.inject context
                    (`Inputs [ Ui_state.Input.File_preview snapshot ]) in
                 let%bind.Effect () = Effect.of_deferred_thunk (fun () -> changed) in
                 pump () in
             Bonsai.Apply_action_context.schedule_event context (pump ()));
          active_file_session := Option.map (Ui_state.file_picker model) ~f:File_picker_tile.session;
          active_line_session := Option.map (Ui_state.line_picker model) ~f:Line_picker_tile.session;
          active_content_session := Option.map (Ui_state.content_picker model) ~f:Content_picker_tile.session;
           let model, clipboard = Ui_state.take_clipboard model in
           let model, harness_requests = Ui_state.take_harness_requests model in
           let model, bsc_request = Ui_state.take_bsc_request model in
           Option.iter bsc_request ~f:(fun request ->
             Bonsai.Apply_action_context.schedule_event context
               (let%bind.Effect result = Effect.of_deferred_thunk (fun () -> Bsc_host.execute bsc request) in
                Bonsai.Apply_action_context.inject context (`Bsc (request, result))));
           List.iter harness_requests ~f:(fun work ->
             Bonsai.Apply_action_context.schedule_event context
               (let%bind.Effect result = Effect.of_deferred_thunk (fun () -> Harness_host.execute harness work) in
                Bonsai.Apply_action_context.inject context (`Harness (work.action, result))));
          let model, snippet_requests = Ui_state.take_snippet_reload_requests model in
          let model, word_request = Ui_state.take_word_index_request model in
          Bonsai.Apply_action_context.schedule_event context
            (Effect.of_thunk (fun () -> Word_index_host.follow word_index word_request));
          if not (List.is_empty snippet_requests) then
            Bonsai.Apply_action_context.schedule_event context
              (Effect.of_thunk (fun () -> Snippet_host.submit snippets snippet_requests));
          let model, configuration_requests = Ui_state.take_config_reload_requests model in
          if not (List.is_empty configuration_requests) then
            Bonsai.Apply_action_context.schedule_event context
              (Effect.of_thunk (fun () -> Configuration_host.submit configuration configuration_requests));
          let model, terminal_requests = Ui_state.take_terminal_session_requests model in
           Option.iter terminal ~f:(fun terminal ->
             if not (List.is_empty terminal_requests) then
               Bonsai.Apply_action_context.schedule_event context
                 (Effect.of_thunk (fun () -> Terminal_host.submit_sessions terminal terminal_requests)));
           let model, toggles = Ui_state.take_external_terminal_toggles model in
            List.iter toggles ~f:(fun number ->
              Bonsai.Apply_action_context.schedule_event context
                (Effect.lazy_ (lazy (on_toggle_terminal number))));
            let model, commands = Ui_state.take_host_command_requests model in
            List.iter commands ~f:(fun id ->
              Bonsai.Apply_action_context.schedule_event context
                (Effect.lazy_ (lazy (on_host_command id))));
          Option.iter clipboard ~f:(fun text ->
            Bonsai.Apply_action_context.schedule_event
              context
               (set_clipboard text));
          (* Requests leave as data: the source is told after this transition, which
             never waits for it. *)
          let model, requests = Ui_state.take_source_requests model in
          Option.iter source ~f:(fun source ->
            List.iter requests ~f:(fun request ->
              Bonsai.Apply_action_context.schedule_event
                context
                (Effect.of_thunk (fun () -> Cobalt_source.Source.send source request))));
          (* Views' jobs leave as data too: the runner gets them after this transition.
             Without a runner, each is answered as never started, so no view waits. *)
          let model, jobs = Ui_state.take_vcs_jobs model in
          if not (List.is_empty jobs) then
            Bonsai.Apply_action_context.schedule_event context
              (match vcs with
               | Some host -> Effect.of_thunk (fun () -> Vcs_host.submit host jobs)
               | None -> Bonsai.Apply_action_context.inject context
                   (`Inputs (List.map jobs ~f:(fun job ->
                      Ui_state.Input.Vcs (Finished (Cobalt_vcs.Job.never_started job))))));
          let model, requests = Ui_state.take_file_requests model in
          List.iter requests ~f:(fun request ->
            Bonsai.Apply_action_context.schedule_event context
              (match file_picker with
               | Some host when not (Ui_state.is_split_file_request request) ->
                 Effect.of_thunk (fun () -> host.consume request)
               | _ -> Bonsai.Apply_action_context.inject context
                   (`Inputs [ Ui_state.Input.File_picker_accept request ])));
          let model, requests = Ui_state.take_content_requests model in
          List.iter requests ~f:(fun request ->
            Bonsai.Apply_action_context.schedule_event context
              (match content_picker with
               | Some host -> Effect.of_thunk (fun () -> host.consume request)
               | None -> Bonsai.Apply_action_context.inject context
                   (`Inputs [ Ui_state.Input.Content_picker_accept request ])));
          if not !picker_turn_scheduled
             && (line_needs_turn model || picker_needs_turn model
                 || Cobalt_content_picker_host.Runtime.needs_turn content_runtime model)
          then (
            picker_turn_scheduled := true;
            Bonsai.Apply_action_context.schedule_event context
              (let%bind.Effect events = Effect.of_deferred_thunk (fun () ->
                 if line_needs_turn model then (
                   let generation = Ui_state.line_picker_generation model in
                   Async.Deferred.map (Async.Scheduler.yield ()) ~f:(fun () ->
                     [ Ui_state.Input.Line_picker_work generation ]))
                 else if Cobalt_content_picker_host.Runtime.needs_turn content_runtime model then
                   Cobalt_content_picker_host.Runtime.next content_runtime model
                 else if picker_needs_turn model then
                   Cobalt_file_picker_host.Runtime.next file_runtime model
                 else Async.return []) in
               picker_turn_scheduled := false;
               (* Obsolete turns still wake replacements, without doing their work. *)
               Bonsai.Apply_action_context.inject context (`Inputs events)));
           current_ui := model;
           (match status with
              | Exit when was_running ->
                stop ();
                Bonsai.Apply_action_context.schedule_event context (exit ())
           | Exit | Running -> ());
           model))
         (let%arr dimensions and set_clipboard and on_toggle_terminal and host_commands
              and on_host_command and accepts_input in
          dimensions, set_clipboard, on_toggle_terminal, host_commands, on_host_command, accepts_input)
      graph
  in
    Option.iter mouse ~f:(fun initial ->
      let reporting = let%arr model in
        if Ui_state.exited model then None else Ui_state.mouse_reporting model in
      let set_reporting = Mouse_reporting.set_mouse_reporting graph in
      (* Notty has already installed [initial] at startup and restores the
         terminal on release. Only write changes while the editor is live. *)
      Bonsai.Edge.on_change' reporting ~equal:(Option.equal Bool.equal)
        ~callback:(let%arr set_reporting in fun previous -> function
          | Some enabled when not (Bool.equal enabled
              (Option.value (Option.join previous) ~default:initial)) ->
            set_reporting (if enabled then All_mouse_events_except_hover else No_mouse_events)
          | _ -> Effect.Ignore)
        graph);
    let inject = let%arr inject_action in fun inputs -> inject_action (`Inputs inputs) in
   Option.iter on_open_location_ready ~f:(fun ready ->
     let project_root = Cobalt_app.Session.project_root (Ui_state.session initial_ui) in
     Bonsai.Edge.lifecycle
       ~on_activate:(let%arr inject_action in
         let on_request request =
           let%map.Async.Deferred result = until_stopping (fun () ->
             let reply = Async.Ivar.create () in
             (* The listener is outside Bonsai; enqueue the same action as [hosted].
                Stop also wakes a request if the terminal loop has stopped flushing. *)
             Effect.Expert.handle ~on_exn:raise (inject_action (`Open_location (request, reply)));
             Async.Ivar.read reply) in
           match result with
           | None | Some (Error `Closed) -> Error Open_location.Session_exited
           | Some (Error (`Open failure)) -> Error failure
           | Some (Ok _) -> Ok ()
         in
         let%bind.Effect result = Effect.of_deferred_thunk (fun () ->
           ready ~project_root ~on_request) in
         match result with
         | Ok () -> Effect.Ignore
         | Error _ when stopped () -> Effect.Ignore
         | Error _ -> exit ())
       graph);
   Bonsai.Edge.lifecycle ~on_deactivate:(Bonsai.return (Effect.of_thunk stop)) graph;
  Bonsai.Edge.lifecycle
    ~on_activate:(let%arr inject_action in
      let rec pump () =
        let%bind.Effect reply = Effect.of_deferred_thunk (fun () -> Word_index_host.next word_index) in
        match reply with
        | None -> Effect.Ignore
        | Some reply -> let%bind.Effect () = inject_action (`Words reply) in pump ()
      in pump ())
    graph;
  Bonsai.Edge.lifecycle
    ~on_activate:(let%arr inject_action in
      let rec pump () =
        let%bind.Effect reply = Effect.of_deferred_thunk (fun () -> Snippet_host.next snippets) in
        match reply with
        | None -> Effect.Ignore
        | Some reply ->
          let%bind.Effect () = inject_action (`Snippets reply) in
          pump ()
      in
      pump ())
    graph;
  Bonsai.Edge.lifecycle
    ~on_activate:(let%arr inject_action in
      let rec pump () =
        let%bind.Effect reply = Effect.of_deferred_thunk (fun () -> Configuration_host.next configuration) in
        match reply with
        | None -> Effect.Ignore
        | Some reply ->
          let%bind.Effect () = inject_action (`Configuration reply) in
          pump ()
      in
      pump ())
    graph;
  Bonsai.Edge.lifecycle ~on_activate:(let%arr inject in inject []) graph;
   Option.iter silver_overview ~f:(fun host ->
     Bonsai.Edge.lifecycle
       ~on_activate:(let%arr inject_action in
         let rec pump () =
           (* Invalidate with the latest cached rows, not a captured snapshot;
              pending notifications cannot reinstall an old binding's rows. *)
           let after = host.revision () in
           let%bind.Effect () = inject_action `Silver_changed in
           let%bind.Effect changed = Effect.of_deferred_thunk (fun () ->
             until_stopping (fun () -> host.await_change ~after)) in
           match changed with None -> Effect.Ignore | Some () -> pump ()
         in
         pump ())
       graph);
  (* Source events enter like keys, as inputs of their own transition, one bounded batch
     at a time, so keys typed during a burst are handled between batches. *)
   Option.iter source ~f:(fun source ->
    Bonsai.Edge.lifecycle
     ~on_activate:(let%arr inject in
        let rec pump () =
          let%bind.Effect events = Effect.of_deferred_thunk (fun () ->
            until_stopping (fun () -> Cobalt_source.Source.next_batch source))
          in
          match events with
          | None -> Effect.Ignore
          | Some events ->
            let%bind.Effect () =
              inject (List.map events ~f:(fun event -> Ui_state.Input.Source event))
            in
            pump ()
        in
        pump ())
      graph);
  (* The runner's events enter the same way, one batch per transition. The next batch
     is asked for only once the previous one is injected; after [stop] none comes, so
     this loop never holds exit open. *)
  Option.iter vcs ~f:(fun host ->
    Bonsai.Edge.lifecycle
      ~on_activate:
        (let%arr inject in
         let rec pump () =
            let%bind.Effect inputs = Effect.of_deferred_thunk (fun () ->
              until_stopping (fun () -> Vcs_host.next_inputs host))
            in
            match inputs with
            | None -> Effect.Ignore
            | Some inputs ->
              let%bind.Effect () = inject inputs in
              pump ()
         in
         pump ())
      graph);
   Option.iter terminal ~f:(fun terminal ->
     Bonsai.Edge.lifecycle
       ~on_activate:(let%arr inject in
         let rec pump () =
           let%bind.Effect event = Effect.of_deferred_thunk (fun () ->
             Terminal_host.next_session_update terminal) in
           match event with
           | None -> Effect.Ignore
           | Some (terminal, generation, event) ->
             let%bind.Effect () = inject [ Ui_state.Input.Terminal_session_update { terminal; generation; event } ] in
             pump ()
         in
         pump ())
       graph);
  let get_current_time = Bonsai.Clock.get_current_time graph in
  Bonsai.Edge.on_change accepts_input ~equal:Bool.equal
    ~callback:(let%arr inject_action in fun accepts_input ->
      if accepts_input then Effect.Ignore else inject_action `Lost_input)
    graph;
  Bonsai.Edge.on_change
    dimensions
    ~equal:(fun (a : Dimensions.t) b -> a.width = b.width && a.height = b.height)
    ~callback:(let%arr inject in fun _ -> inject [ Ui_state.Input.Resize ])
    graph;
   let closed = let%arr model in Ui_state.exited model in
   let (_ : unit Bonsai.t) =
     match%sub closed with
     | true -> Bonsai.return ()
     | false ->
       Bonsai.Clock.every
         ~when_to_start_next_effect:`Every_multiple_of_period_non_blocking
         ~trigger_on_activate:true
         (Bonsai.return (Time_ns.Span.of_ms 17.))
          (let%arr inject and get_current_time in
           let%bind.Effect now = get_current_time in
           (* Read the transition's latest state, including keys delivered since the
              last display. Deadlines still run while the pane is hidden. *)
           let model = !current_ui in
           let inputs =
             (if Ui_state.toggle_key_pending model then [ Ui_state.Input.Toggle_tick now ] else [])
             @ (if Ui_state.terminal_key_pending model then [ Ui_state.Input.Terminal_tick now ] else [])
             @ (if Animation.active (Ui_state.animation model)
                then [ Ui_state.Input.Animation_tick now ] else []) in
           if List.is_empty inputs then Effect.Ignore else inject inputs)
         graph;
       Bonsai.return ()
   in
     let stage_spinner_visible =
       (let%arr model and visible and { Dimensions.width; height } = dimensions in
        visible && Ui_state.silver_stage_spinner_visible model ~width ~height)
       |> Bonsai.cutoff ~equal:Bool.equal
     in
     (* This clock exists only while a spinner can be seen. It feeds rendering,
        not the input/action path, so it cannot trigger any provider work. *)
     let stage_spinner =
       match%sub stage_spinner_visible with
       | false -> Bonsai.return None
       | true ->
         let now = Bonsai.Clock.approx_now ~tick_every:Silver_stage_tile.Spinner.period graph in
         (let%arr now in Some (Silver_stage_tile.Spinner.at now))
         |> Bonsai.cutoff ~equal:(Option.equal Silver_stage_tile.Spinner.equal)
     in
     let surface =
      let%arr model
      and { Dimensions.width; height } = dimensions
       and appearance and stage_spinner
      and visible and focused in
     if (blank_on_close && Ui_state.exited model) || not visible || width = 0 || height = 0
     then View.none, None
     else (
        let theme = Option.value_or_thunk appearance ~default:(fun () -> Ui_state.theme model) in
       if not (Option.equal Cobalt_theme.Theme.equal !last_drawn_theme (Some theme))
       then (
         Frame.Cache.invalidate render_cache;
         last_drawn_theme := Some theme);
       let frame, base =
          Frame.Cache.get ?stage_spinner
            ?decorations:(Document_decoration_host.decorations ~width ~height document_decorations model)
           render_cache model ~width ~height ~draw_base:(draw_base ~theme ?font)
       in
       let view = if focused then draw_overlay ~theme ?font ~base frame else base in
       let view = fit_view view ~width ~height in
       let cursor = Option.filter (cursor frame) ~f:(fun { Cursor.position = { x; y }; _ } ->
         focused && x >= 0 && x < width && y >= 0 && y < height) in
       view, cursor)
   in
   let%arr closed and view, cursor = surface and inject_action and get_current_time in
   let handle_event event =
       (* Date the event before it queues; normalization uses that same timestamp
          for every resulting key and the same clock as timeout ticks. *)
       let%bind.Effect at = get_current_time in
       inject_action (`Event (event, at))
   in
   let open_location request =
     let%bind.Effect reply = Effect.of_thunk Async.Ivar.create in
     let%bind.Effect () = inject_action (`Open_location (request, reply)) in
     Effect.of_deferred_thunk (fun () -> Async.Ivar.read reply)
   in
   let shutdown () =
     let%bind.Effect () = inject_action `Shutdown in
     Effect.of_deferred_thunk (fun () -> Async.Ivar.read finished)
   in
   { view; cursor; handle_event; open_location; shutdown; closed }
;;

let hosted ?layout ?terminal ?snippets ?configuration ?startup_configuration ?configuration_path
    ?document_decorations ?document_decorations_enabled ?smear_enabled ?zen ?bare ?theme ?appearance
    ?buffer_presentation ?report ?source ?vcs ?font ?file_picker ?content_picker ?on_toggle_terminal
    ?host_commands ?on_host_command
    ?(set_clipboard = Bonsai.return (fun _ -> Effect.Ignore))
    controller ~dimensions ~visible ~focused (local_ graph) =
  let terminal = match terminal, on_toggle_terminal with
    | None, None -> Some (Terminal_host.create ())
    | _ -> terminal in
  let vcs = Option.value_or_thunk vcs ~default:Vcs_host.create in
  (* Like standalone, the workspace source starts no process until the first
     supported document opens. The component owns it, not the outer host. *)
  let source = Option.value_or_thunk source ~default:(fun () ->
    Cobalt_source.Lsp_client.start_workspace ~cell_width:Cell_map.width ()) in
  component ?layout ?terminal ?snippets ?configuration ?startup_configuration ?configuration_path
    ?document_decorations ?document_decorations_enabled ?smear_enabled ?zen ?bare ?theme ?appearance
     ?buffer_presentation ?report ~source ~vcs ?font ?file_picker ?content_picker ?on_toggle_terminal
      ?host_commands ?on_host_command ~hosted_silver_navigation:true ~set_clipboard
    controller ~exit:(fun () -> Effect.Ignore) ~blank_on_close:true ~dimensions ~visible ~focused graph
;;

let app_with_terminal ~terminal ?snippets ?configuration ?startup_configuration ?configuration_path
    ?document_decorations ?document_decoration_host ?document_decorations_enabled ?smear_enabled
    ?mouse ?zen ?bare ?theme ?buffer_presentation ?report ?source ?vcs ?font ?file_picker ?content_picker
    ?silver_overview ?force_startup_silver_overview ?on_open_location_ready controller ~exit ~dimensions (local_ graph) =
  let set_clipboard =
    let%arr write = Expert.Write_to_tty.write_string_to_tty graph in
    fun text -> write (Osc52.set_clipboard text)
  in
  let surface = component ~terminal ?snippets ?configuration ?startup_configuration ?configuration_path
      ?document_decorations ?document_decoration_host ?document_decorations_enabled ?smear_enabled
      ?mouse ?zen ?bare ?theme ?buffer_presentation ?report ?source ?vcs ?font ?file_picker ?content_picker
       ?silver_overview ?force_startup_silver_overview ?on_open_location_ready ~standalone_layouts:true
       ~set_clipboard controller ~exit ~blank_on_close:false ~dimensions ~visible:(Bonsai.return true)
      ~focused:(Bonsai.return true) graph in
  let set_cursor = Effect.set_cursor graph in
  Bonsai.Edge.after_display (let%arr surface and set_cursor in set_cursor surface.cursor) graph;
  let view = let%arr surface in surface.view in
  let handler = let%arr surface in surface.handle_event in
  ~view, ~handler
;;

let app ?terminal ?snippets ?configuration ?startup_configuration ?configuration_path ?document_decorations ?document_decorations_enabled ?smear_enabled ?(zen = false) ?bare ?theme ?buffer_presentation ?report ?source ?vcs ?font
  ?file_picker ?content_picker controller ~exit ~dimensions (local_ graph) =
  let terminal = Option.value_or_thunk terminal ~default:Terminal_host.create in
  app_with_terminal ~terminal ?snippets ?configuration ?startup_configuration ?configuration_path ?document_decorations ?document_decorations_enabled ?smear_enabled ~zen ?bare ?theme ?buffer_presentation
    ?report ?source ?vcs ?font ?file_picker ?content_picker controller ~exit ~dimensions graph
;;

let run ?configuration ?startup_configuration ?configuration_path ?document_decorations ?document_decorations_enabled ?(smear_enabled = false) ?(mouse = true) ?(zen = false) ?bare ?theme ?font ?buffer_presentation ?report ?(silver_overview : Silver_overview_host.t option) ?force_startup_silver_overview ?source ?vcs ?(open_location_listener : open_location_listener option) controller =
  let document_decoration_host = Document_decoration_host.create
    (Option.value document_decorations ~default:Document_decoration_host.Factory.unavailable) in
  let decorations_at_shutdown = ref (Some document_decoration_host) in
  let silver_at_shutdown = ref silver_overview in
  let stop_silver () =
    Option.iter !silver_at_shutdown ~f:(fun host -> host.shutdown ());
    silver_at_shutdown := None
  in
  Option.iter silver_overview ~f:(fun _ ->
    Async.Shutdown.at_shutdown (fun () -> stop_silver (); Async.return ()));
  Async.Shutdown.at_shutdown (fun () ->
    Option.iter !decorations_at_shutdown ~f:Document_decoration_host.clear;
    decorations_at_shutdown := None;
    Async.return ());
  let configuration = Option.value_or_thunk configuration ~default:(fun () -> Configuration_host.create ()) in
  let configuration_at_shutdown = ref (Some configuration) in
  Async.Shutdown.at_shutdown (fun () ->
    match !configuration_at_shutdown with
    | None -> Async.return ()
    | Some host ->
      let%map.Async.Deferred () = Configuration_host.shutdown host in
      configuration_at_shutdown := None);
  (* Also cover startup helpers: Async shutdown lets the loader reap children.
     Once mounted, terminal shutdown restores raw mode and the alternate screen. *)
  Async.Signal.handle
    [ Async.Signal.term; Async.Signal.hup; Async.Signal.int; Async.Signal.quit ]
    ~f:(fun (_ : Signal.t) -> Async.shutdown 1);
  let%bind.Async.Deferred startup_configuration = match startup_configuration with
    | Some result -> Async.return result
    | None -> Configuration_host.startup configuration in
  let terminal = Terminal_host.create () in
  (* Shutdown hooks outlive [run]; release their runtime reference after cleanup. *)
  let terminal_at_shutdown = ref (Some terminal) in
  Async.Shutdown.at_shutdown (fun () ->
    match !terminal_at_shutdown with
    | None -> Async.return ()
    | Some terminal ->
      let%map.Async.Deferred () = Terminal_host.shutdown terminal in
      terminal_at_shutdown := None);
  (* However the process ends, git children get their termination grace, so none is
     left holding [index.lock]. Idempotent with the wait below. *)
  Option.iter vcs ~f:(fun host ->
    Async.Shutdown.at_shutdown (fun () ->
      Async.Deferred.ignore_m (Vcs_host.shutdown host)));
  let listener = ref None in
  let listener_closing = ref false in
  let listener_error = ref None in
  let stop_listener () =
    listener_closing := true;
    match !listener with
    | None -> Async.return ()
    | Some starting ->
      let%bind.Async.Deferred result = starting in
      let%map.Async.Deferred () = match result with
        | Error _ -> Async.return ()
        | Ok stop -> stop () in
      listener := None
  in
  let on_open_location_ready = Option.map open_location_listener ~f:(fun start ->
    Async.Shutdown.at_shutdown stop_listener;
    fun ~project_root ~on_request ->
      if !listener_closing then Async.return (Or_error.error_string "Editor is shutting down")
      else (
        let on_request request =
          if !listener_closing then Async.return (Error Open_location.Session_exited)
          else on_request request in
        let starting = start ~project_root ~on_request in
        listener := Some starting;
        let%map.Async.Deferred result = starting in
        match result with
        | Ok _ -> Ok ()
        | Error error -> listener_error := Some error; Error error))
  in
  Async.Deferred.bind
    (Bonsai_term.start_with_exit
       ~dispose:true
       ~mouse:(if mouse then All_mouse_events_except_hover else No_mouse_events)
       ~bpaste:true
          (app_with_terminal ~terminal ~configuration ~startup_configuration ?configuration_path ~document_decoration_host ?document_decorations_enabled ~smear_enabled ~mouse ~zen ?bare ?theme ?buffer_presentation ?report ?silver_overview ?force_startup_silver_overview ?source ?vcs ?font ?on_open_location_ready controller))
      ~f:(fun result ->
       stop_silver ();
       let%bind.Async.Deferred () = stop_listener () in
       Document_decoration_host.clear document_decoration_host;
       decorations_at_shutdown := None;
      Configuration_host.stop configuration;
      Option.iter source ~f:Cobalt_source.Source.stop;
      Cobalt_app.Controller.close controller;
      let%bind.Async.Deferred () = Terminal_host.shutdown terminal in
      terminal_at_shutdown := None;
      let%bind.Async.Deferred () = Configuration_host.shutdown configuration in
      configuration_at_shutdown := None;
      let%map.Async.Deferred (_ : [ `Finished | `Timed_out ]) =
        match vcs with
        | None -> Async.return `Finished
        | Some host -> Vcs_host.shutdown host
      in
       match !listener_error with
       | Some error -> Error error
       | None -> result)
;;
