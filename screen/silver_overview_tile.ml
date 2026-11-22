open! Core
open Cobalt_input
module Navigation = Cobalt_tile.Navigation
module Selection = Navigation.Selection

let id = Cobalt_tile.View_id.of_string "silver-overview"
let title = "Silver: Overview"
let spec = Cobalt_tile.Spec.read_only id ~title

module Display_row = struct
  type tone = Plain | Positive | Active | Caution | Negative | Muted [@@deriving sexp_of]

  type t =
    | Message of string * tone
    | Field of { key : string; value : string; tone : tone }
  [@@deriving sexp_of]

  let message ?(tone = Plain) text = Message (text, tone)
  let field ?(tone = Plain) key value = Field { key; value; tone }

  let style : tone -> Style.t = function
    | Plain -> Status
    | Positive -> Diff_added
    | Active -> Pending
    | Caution -> Warning
    | Negative -> Error
    | Muted -> Stale
  ;;
end

module Field = struct
  type t = { name : string; value : string; default : string } [@@deriving sexp_of, equal]
end

module Target = struct
  type t =
    { suite : string
    ; variant : string option
    ; digest : string
    ; fields : Field.t list
    }
  [@@deriving sexp_of, equal]

  let name t =
    Option.value_map t.variant ~default:t.suite ~f:(sprintf "%s / %s" t.suite)
  ;;

  let summary t =
    let overrides =
      List.filter_map t.fields ~f:(fun field ->
        Option.some_if (not (String.equal field.value field.default))
          (sprintf "%s=%s" field.name field.value))
    in
    String.concat ~sep:" · " (name t :: overrides)
  ;;
end

module Test_action = struct
  type t = Run of Target.t | Pick | Unavailable of string [@@deriving sexp_of, equal]

  let title = function
    | Run target -> "Run test · " ^ Target.summary target
    | Pick -> "Run test · Choose a suite or variant"
    | Unavailable reason -> "Run test · Unavailable: " ^ reason
  ;;
end

module Connection = struct
  module Id = struct
    type t = int [@@deriving sexp_of, equal]
    let of_int n = n
  end

  type row = { id : Id.t; title : string }
  type lookup = { rows : row list; error : string option }

  type selection =
    | Share of Id.t
    | Manual of { endpoint : string; project_root : string }
  [@@deriving sexp_of, equal]
end

module Intent = struct
  type t =
    | Refresh
    | Launch of Target.t
    | Apply_settings of Target.t * (string * string) list
    | Connections of int
    | Connect of { generation : int; selection : Connection.selection }
  [@@deriving sexp_of, equal]
end

module Row = struct
  type t = Target of string * string option | Status of int [@@deriving sexp_of, equal]
end

type t =
  { display_rows : Display_row.t list
  ; targets : Target.t list
  ; status_first : bool
  ; view : Row.t Selection.t
  ; intents : Intent.t list
  ; selection_stale : bool
  }
[@@deriving sexp_of]

let with_rows t display_rows = { t with display_rows }
let with_status_first t status_first = { t with status_first }
let targets t = t.targets
let take_intents t = { t with intents = [] }, List.rev t.intents
let enqueue t intent = { t with intents = intent :: t.intents }
let key = Type_equal.Id.create ~name:"silver-overview" sexp_of_t
let row_key (target : Target.t) = Row.Target (target.suite, target.variant)

let items t =
  let targets = List.map t.targets ~f:(fun target -> row_key target, `Target target) in
  let status = List.mapi t.display_rows ~f:(fun i row -> Row.Status i, `Status row) in
  if t.status_first then status @ targets else targets @ status
;;

let ids t = List.map (items t) ~f:fst
let fit t ~rows = { t with view = Selection.fit t.view (ids t) ~equal:Row.equal ~rows }

let selected_target t =
  Option.bind t.view.selected ~f:(fun selected ->
    List.find t.targets ~f:(fun target -> Row.equal selected (row_key target)))
;;

let with_targets t targets =
  if List.is_empty t.targets && not (List.is_empty targets)
  then { t with targets; view = Selection.empty }
  else
    let selection_stale =
      t.selection_stale
      || Option.exists (selected_target t) ~f:(fun previous ->
        not (List.exists targets ~f:(fun target ->
          Row.equal (row_key target) (row_key previous)
          && String.equal target.digest previous.digest)))
    in
    { t with targets; selection_stale }
;;

type action =
  | Move of Navigation.Motion.t
  | Refresh
  | Launch
  | Edit_settings
  | Apply_settings of Target.t * (string * string) list

let refresh = Key.char 'r'
let launch = Key.char 'R'

let interpret _ = function
  | [ key ] when Key.equal key refresh -> Cobalt_tile.Content_key.Action Refresh
  | [ key ] when Key.equal key launch -> Cobalt_tile.Content_key.Action Launch
  | [ Key.Enter ] -> Cobalt_tile.Content_key.Action Edit_settings
  | keys -> Cobalt_tile.Content_key.map (Navigation.interpret keys) ~f:(fun move -> Move move)
;;

let display_row = function
  | `Status row -> row
  | `Target (target : Target.t) ->
    (match target.variant with
     | None -> Display_row.field "Suite" target.suite
     | Some variant -> Display_row.field "Variant" variant)
;;

let cells text = Cell_map.total_width (Cell_map.glyphs text)

let column_width items ~width =
  let preferred =
    List.fold items ~init:0 ~f:(fun longest (_, row) ->
      match display_row row with
      | Message _ -> longest
      | Field { key; _ } -> Int.max longest (cells key))
  in
  (* Budget a colon and a gap, and give values at least half the space in a
     narrow tile. If only a few cells remain, show the value alone. *)
  Int.min preferred (Int.max 0 (width - 2 - Int.min 10 (width / 2)))
;;

let render_row row ~selected ~width ~marker_width ~key_width =
  let marker = Tile_text.row Pending (if selected then "›" else "") ~width:marker_width in
  let width = width - marker_width in
  let body =
    match display_row row with
    | Message (text, tone) -> Tile_text.row (Display_row.style tone) text ~width
    | Field { key; value; tone } ->
      let value_style =
        match row with
        | `Target _ when selected -> Style.Pending
        | _ -> Display_row.style tone
      in
      if key_width = 0
      then Tile_text.row value_style value ~width
      else (
        let key_cells = Int.min key_width (cells key) in
        Tile_text.row Status_special key ~width:key_cells
        @ Tile_text.row Status_special ":" ~width:(key_width - key_cells + 2)
        @ Tile_text.row value_style value ~width:(width - key_width - 2))
  in
  Span.merge (marker @ body)
;;

let adapter : (t, action) View_registry.Adapter.t =
  { spec
  ; key
  ; fit = (fun t _ ~rows ~width:_ -> fit t ~rows)
  ; leave = Fn.id
  ; text_view = (fun _ -> None)
  ; interpret
  ; escape = (fun _ -> None)
   ; hint = "Silver: Overview — j/k select, R runs, Enter edits settings, r refreshes, Escape returns"
  ; perform = (fun t controller ~context:_ ~rows ~width:_ action ->
      let t = fit t ~rows in
      let done_ t = t, View_registry.Outcome.create controller in
      let notice text = t, View_registry.Outcome.create controller ~notice:(`Post text) in
      let no_target () = notice "Select a test suite or variant" in
      let stale () = notice "Silver catalog changed; select the test row again" in
      match action with
      | Refresh -> done_ (enqueue t Intent.Refresh)
      | Move motion ->
        done_ { t with view = Selection.move t.view (ids t) ~equal:Row.equal ~rows motion
                     ; selection_stale = false }
      | (Launch | Edit_settings) when t.selection_stale -> stale ()
      | Launch ->
        (match selected_target t with
         | Some target -> done_ (enqueue t (Intent.Launch target))
         | None -> no_target ())
      | Edit_settings ->
        (match selected_target t with
         | None -> no_target ()
         | Some target ->
           let fields = List.map target.fields ~f:(fun field -> field.name, field.value) in
           let ask =
             View_registry.Ask.Form
               { title = "Test settings · " ^ Target.name target
               ; fields
               ; accept = (fun values -> Apply_settings (target, values))
               }
           in
           t, View_registry.Outcome.create controller ~ask)
      | Apply_settings (target, fields) -> done_ (enqueue t (Intent.Apply_settings (target, fields))))
  ; commands = (fun t ->
       let refresh = Cobalt_tile.Local_command.create "refresh" ~keys:[ refresh ] "Refresh Silver: Overview" in
      let target_commands =
        if List.is_empty t.targets then []
        else
          [ Cobalt_tile.Local_command.create "run-test-row" ~keys:[ launch ] "Run selected test"
          ; Cobalt_tile.Local_command.create "edit-test-settings" ~keys:[ Enter ] "Edit selected test settings"
          ]
      in
      refresh :: target_commands @ Navigation.commands)
  ; signal = (fun _ _ -> None)
  ; label = (fun _ -> None)
  ; text_area = (fun _ ~rows:_ ~width:_ -> None)
   ; render = (fun t _ ~hotkey_hints ~focused ~notice ~pending ~width ~rows ->
       let view = (fit t ~rows).view in
       let top = if focused then view.top else 0 in
       let items = items t in
       let width = Int.max 0 width in
       let marker_width = Int.clamp_exn (width - 1) ~min:0 ~max:2 in
       let key_width = column_width items ~width:(width - marker_width) in
       let body =
         List.take (List.drop items top) (Int.max 0 rows)
         |> List.map ~f:(fun (key, row) ->
           let selected = focused && Option.exists view.selected ~f:(Row.equal key) in
           render_row row ~selected ~width ~marker_width ~key_width)
      in
      let default =
        if not hotkey_hints && (List.is_empty t.targets || not focused) then ""
        else if focused && List.is_empty t.targets then "j/k r Esc | Space v S: close"
        else if focused then "j/k select | R run | Enter settings | r refresh | Esc"
        else "Space v U: focus; v S: close"
      in
      { title; body; footer = Some (Tile_shell.Label.footer ~notice ~pending ~default) })
  }
;;

let entry ?(targets = []) ?(status_first = false) display_rows =
  View_registry.Entry.install ~placement:Band adapter
    { display_rows; targets; status_first; view = Selection.empty
    ; intents = []; selection_stale = false }
;;
