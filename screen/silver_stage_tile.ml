open! Core
open Cobalt_input
module Navigation = Cobalt_tile.Navigation
module Selection = Navigation.Selection

let id = Cobalt_tile.View_id.of_string "silver-stage"
let title = "Silver: Stage Checklist"
let adapter_unavailable = "Silver adapter not built"
let spec = Cobalt_tile.Spec.read_only id ~title

module Alias = struct
  type t = Synth | Timing | Routing [@@deriving sexp_of, equal]

  let all = [ Synth; Timing; Routing ]

  let query = function
    | Synth -> "synth"
    | Timing -> "timing"
    | Routing -> "routing"
  ;;

  let command_id t = "silver.stage." ^ query t
end

module Intent = struct
  type t = { token : string; selection : string; summary : string } [@@deriving sexp_of, equal]
end

module Action = struct
  type t = Ready of Intent.t | Blocked of string [@@deriving sexp_of, equal]

  let title alias action =
    "Run " ^ Alias.query alias ^ " · "
    ^ (match action with
       | Ready intent -> intent.summary
       | Blocked reason -> "Unavailable: " ^ reason)
  ;;
end

module Spinner = struct
  type t = int [@@deriving equal, sexp_of]

  (* Native Silver Overview's Bonsai_term Dot cycle. Derive the frame from
     the clock so a delayed render skips frames rather than slowing the cycle. *)
  let frames = [| "⣷"; "⣯"; "⣟"; "⡿"; "⢿"; "⣻"; "⣽"; "⣾" |]
  let first = 0
  let period = Time_ns.Span.of_ms 100.

  let at now =
    let open Int63 in
    let ticks = Time_ns.to_int63_ns_since_epoch now / Time_ns.Span.to_int63_ns period in
    to_int_exn (ticks % of_int (Array.length frames))
  ;;

  let marker frame = frames.(frame)
end

module Status = struct
  type t =
    | Unknown
    | Not_requested
    | Pending
    | Running
    | Cancelling
    | Completed
    | Failed
    | Skipped
    | Cancelled
    | Interrupted
    | Unsupported
    | Unrecognized of string
  [@@deriving sexp_of, equal]

  (* Match the native Overview checklist's status roles and Unicode markers.
     This mapping must not depend on the launch action. *)
  let spinning = function
    | Running | Cancelling -> true
    | Unknown | Not_requested | Pending | Completed | Failed | Skipped | Cancelled
    | Interrupted | Unsupported | Unrecognized _ -> false
  ;;

  let display ?(frame = Spinner.first) : t -> Style.t * string * string = function
    | Unknown -> Stale, "?", "not reported"
    | Not_requested -> Stale, "·", "not requested"
    | Pending -> Warning, "◷", "pending"
    | Running -> Pending, Spinner.marker frame, "running"
    | Cancelling -> Pending, Spinner.marker frame, "cancelling…"
    | Completed -> Diff_added, "✓", "completed"
    | Failed -> Error, "!", "failed"
    | Skipped -> Warning, "↷", "skipped"
    | Cancelled -> Warning, "×", "cancelled"
    | Interrupted -> Warning, "?", "interrupted"
    | Unsupported -> Stale, "?", "unsupported"
    | Unrecognized ("observation_unavailable" | "unconfirmed") ->
      Stale, "?", "unconfirmed"
    | Unrecognized "not_started" -> Stale, "?", "not started"
    | Unrecognized "unavailable" -> Stale, "?", "unavailable"
    | Unrecognized value -> Stale, "?", "unknown: " ^ value
  ;;
end

module Row = struct
  type t = { id : string; label : string; status : Status.t; action : Action.t }
  [@@deriving sexp_of]

  let display_label t = if String.equal t.id "cts" then "CTS" else t.label
end

module Snapshot = struct
  type t =
    { rows : Row.t list
    ; empty : string
    ; aliases : (Alias.t * Action.t) list
    ; context : string option
    ; watch_context : string option
    }
  [@@deriving sexp_of]

  let unavailable reason =
    { rows = []; empty = reason; aliases = []; context = None; watch_context = None }
  ;;

  let alias t alias =
    List.Assoc.find t.aliases alias ~equal:Alias.equal
    |> Option.value ~default:(Action.Blocked t.empty)
  ;;
end

module Watch = struct
  type t = Older | Newer | Latest | Refresh [@@deriving sexp_of]
end

type t =
  { snapshot : Snapshot.t
  ; view : string Selection.t
  ; intents : Intent.t list
  ; watches : Watch.t list
  ; selection_stale : bool
  ; spinner : Spinner.t
  }
[@@deriving sexp_of]

let key = Type_equal.Id.create ~name:"silver-stage" sexp_of_t
let enqueue t intent = { t with intents = intent :: t.intents }
let take_intents t = { t with intents = [] }, List.rev t.intents
let take_watches t = { t with watches = [] }, List.rev t.watches
let with_spinner t spinner = { t with spinner }
let ids t = List.map t.snapshot.rows ~f:(fun row -> row.id)
let fit t ~rows = { t with view = Selection.fit t.view (ids t) ~equal:String.equal ~rows }

let contexts t =
  if List.is_empty t.snapshot.rows then [] else
    List.filter_opt [ t.snapshot.context; t.snapshot.watch_context ]

let header t ~rows = List.take (contexts t) (Int.max 0 (rows - 1))
let stage_rows t ~rows = rows - List.length (header t ~rows)

let row t id = List.find t.snapshot.rows ~f:(fun row -> String.equal row.id id)
let selected_row t = Option.bind t.view.selected ~f:(row t)

let with_snapshot ?(flow_selected = false) t snapshot =
  let next = { t with snapshot } in
  let selection_stale =
    t.selection_stale
    || Option.exists (selected_row t) ~f:(fun previous ->
      match previous.action, row next previous.id with
       (* A new one-shot token or deliberate flow choice may keep the same stage
          row. A withdrawn or previously stale stage is never accepted here. *)
       | Ready before, Some { action = Ready after; _ } ->
         not (flow_selected || String.equal before.selection after.selection)
       | Ready _, _ | Blocked _, None -> true
       | Blocked _, Some _ -> false)
  in
  { next with selection_stale }
;;

type action = Move of Navigation.Motion.t | Run | Watch of Watch.t

let run_key = Key.char 'R'
let watch_keys =
  [ Key.char '[', Watch.Older, "previous-asic-run", "Watch older matching ASIC run"
  ; Key.char ']', Watch.Newer, "next-asic-run", "Watch newer matching ASIC run"
  ; Key.char 'L', Watch.Latest, "follow-latest-asic-run", "Follow latest matching ASIC run"
  ; Key.char 'r', Watch.Refresh, "refresh-asic-progress", "Refresh ASIC progress"
  ]
;;

let interpret _ keys =
  let navigation () =
    Cobalt_tile.Content_key.map (Navigation.interpret keys) ~f:(fun move -> Move move)
  in
  match keys with
  | [ key ] when Key.equal key run_key -> Cobalt_tile.Content_key.Action Run
  | [ key ] ->
    (match List.find watch_keys ~f:(fun (binding, _, _, _) -> Key.equal key binding) with
     | Some (_, watch, _, _) -> Cobalt_tile.Content_key.Action (Watch watch)
     | None -> navigation ())
  | _ -> navigation ()
;;

let selection_width = 2
let marker_width = 2
let separator_width = 2
let cells text = Cell_map.total_width (Cell_map.glyphs text)

let visible_rows t ~focused ~rows =
  let rows = stage_rows t ~rows in
  let view = (fit t ~rows).view in
  let top = if focused then view.top else 0 in
  view, List.take (List.drop t.snapshot.rows top) (Int.max 0 rows)
;;

let spinner_visible t ~focused ~rows ~width ~covered =
  width > selection_width
  && (let offset = List.length (header t ~rows) in
      let _, visible = visible_rows t ~focused ~rows in
      Option.is_some (List.findi visible ~f:(fun index row ->
        Status.spinning row.status
        && not (covered ~column:selection_width ~row:(offset + index)))))
;;

let status_budget rows =
  List.fold rows ~init:0 ~f:(fun longest (row : Row.t) ->
    let _, _, status = Status.display row.status in
    (* A raw provider status need not force every label out of the pane. *)
    Int.max longest (Int.min (String.length "not requested") (cells status)))
;;

let label_width rows ~width ~status_budget =
  let preferred =
    List.fold rows ~init:0 ~f:(fun longest (row : Row.t) ->
      Int.max longest (cells (Row.display_label row)))
  in
  (* Clip long stage names before status keywords; keep enough of the label
     column for CTS. The whole catalog determines the columns, not the page. *)
  let available = width - selection_width - marker_width - separator_width - status_budget in
  Int.min preferred (Int.clamp_exn available ~min:3 ~max:24)
;;

let render_row (row : Row.t) ~frame ~selected ~stale ~width ~label_width ~status_budget =
  let style, marker, status = Status.display row.status ~frame in
  let stale = selected && stale in
  let remaining = ref (Int.max 0 width) in
  let field style text width =
    let width = Int.min width !remaining in
    remaining := !remaining - width;
    Tile_text.row style text ~width
  in
  let selection =
    if stale then field Warning "›!" selection_width
    else field Pending (if selected then "›" else "") selection_width
  in
  let marker = field style marker marker_width in
  let label_style = if selected then Style.Pending else Status in
  let label = Row.display_label row in
  (* Attach the colon to each label before padding, like native Silver. *)
  let label_cells = Int.min label_width (cells label) in
  let label = field label_style label label_cells in
  let separator = field label_style ":" (label_width - label_cells + separator_width) in
  let status =
    field style status (if stale then Int.max status_budget (cells status) else !remaining)
  in
  let reselect = field Warning (if stale then "  Reselect" else "") !remaining in
  Span.merge (selection @ marker @ label @ separator @ status @ reselect)
;;

let adapter : (t, action) View_registry.Adapter.t =
  { spec
  ; key
  ; fit = (fun t _ ~rows ~width:_ -> fit t ~rows:(stage_rows t ~rows))
  ; leave = Fn.id
  ; text_view = (fun _ -> None)
  ; interpret
  ; escape = (fun _ -> None)
  ; hint = title ^ ": j/k select, R runs through the selected stage, Escape returns"
  ; perform = (fun t controller ~context:_ ~rows ~width:_ action ->
       let rows = stage_rows t ~rows in
       let t = fit t ~rows in
      let done_ t = t, View_registry.Outcome.create controller in
       let blocked reason =
        t, View_registry.Outcome.create controller ~notice:(`Post (reason ^ "; nothing ran"))
      in
       match action with
       | Watch watch -> done_ { t with watches = watch :: t.watches }
      | Move motion ->
        done_
          { t with
            view = Selection.move t.view (ids t) ~equal:String.equal ~rows motion
          ; selection_stale = false
          }
      | Run ->
        (match selected_row t with
         | None -> blocked t.snapshot.empty
         | Some { action = Blocked reason; _ } -> blocked reason
         | Some { action = Ready _; _ } when t.selection_stale ->
           blocked "Silver stage selection changed; select a stage again"
         | Some { action = Ready intent; _ } -> done_ (enqueue t intent)))
  ; commands = (fun _ ->
      Cobalt_tile.Local_command.create "run-stage" ~keys:[ run_key ]
        "Run through selected Silver stage"
       :: List.map watch_keys ~f:(fun (key, _, id, title) ->
            Cobalt_tile.Local_command.create id ~keys:[ key ] title)
       @ Navigation.commands)
  ; signal = (fun _ _ -> None)
  ; label = (fun _ -> None)
  ; text_area = (fun _ ~rows:_ ~width:_ -> None)
  ; render = (fun t _ ~hotkey_hints ~focused ~notice ~pending ~width ~rows ->
      let body =
         match t.snapshot.rows with
         | [] when rows > 0 -> [ Tile_text.row Stale t.snapshot.empty ~width ]
         | rows_data ->
            let header =
              List.map (header t ~rows) ~f:(Tile_text.row Status ~width)
           in
            let view, visible = visible_rows t ~focused ~rows in
           let status_budget = status_budget rows_data in
           let label_width = label_width rows_data ~width ~status_budget in
           header
            @ List.map visible ~f:(fun row ->
                let selected = focused && Option.exists view.selected ~f:(String.equal row.id) in
                render_row row ~frame:t.spinner ~selected ~stale:t.selection_stale
                  ~width ~label_width ~status_budget)
       in
       let hints =
          Option.some_if (focused || hotkey_hints) "j/k stage | R run | [/] ASIC run | L latest | r refresh | Esc"
       in
        let compact_context = List.drop (contexts t) (List.length (header t ~rows)) in
        let default = String.concat ~sep:" | " (compact_context @ Option.to_list hints) in
      { title; body; footer = Some (Tile_shell.Label.footer ~notice ~pending ~default) })
  }
;;

let entry snapshot =
  View_registry.Entry.install adapter
    { snapshot; view = Selection.empty; intents = []; watches = []; selection_stale = false
    ; spinner = Spinner.first }
;;
