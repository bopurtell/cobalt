open! Core
open Cobalt_input
module Navigation = Cobalt_tile.Navigation
module Selection = Navigation.Selection

let id = Cobalt_tile.View_id.of_string "silver-overview"
let title = "Silver overview"
let spec = Cobalt_tile.Spec.read_only id ~title

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

module Intent = struct
  type t =
    | Refresh
    | Launch of Target.t
    | Apply_settings of Target.t * (string * string) list
    | Connections of int
    | Connect of { endpoint : string; project_root : string }
  [@@deriving sexp_of, equal]
end

module Row = struct
  type t = Target of string * string option | Status of int [@@deriving sexp_of, equal]
end

type t =
  { lines : string list
  ; targets : Target.t list
  ; status_first : bool
  ; view : Row.t Selection.t
  ; intents : Intent.t list
  ; selection_stale : bool
  }
[@@deriving sexp_of]

let with_rows t lines = { t with lines }
let with_status_first t status_first = { t with status_first }
let targets t = t.targets
let take_intents t = { t with intents = [] }, List.rev t.intents
let enqueue t intent = { t with intents = intent :: t.intents }
let key = Type_equal.Id.create ~name:"silver-overview" sexp_of_t
let row_key (target : Target.t) = Row.Target (target.suite, target.variant)

let items t =
  let targets = List.map t.targets ~f:(fun target -> row_key target, `Target target) in
  let status = List.mapi t.lines ~f:(fun i line -> Row.Status i, `Status line) in
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

let adapter : (t, action) View_registry.Adapter.t =
  { spec
  ; key
  ; fit = (fun t _ ~rows ~width:_ -> fit t ~rows)
  ; leave = Fn.id
  ; text_view = (fun _ -> None)
  ; interpret
  ; escape = (fun _ -> None)
  ; hint = "Silver overview: j/k select, R runs, Enter edits settings, r refreshes, Escape returns"
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
      let refresh = Cobalt_tile.Local_command.create "refresh" ~keys:[ refresh ] "Refresh Silver overview" in
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
      let body =
        List.take (List.drop (items t) top) (Int.max 0 rows)
        |> List.map ~f:(fun (key, row) ->
          let selected = focused && Option.exists view.selected ~f:(Row.equal key) in
          match row with
          | `Status line -> Tile_text.row (if selected then Pending else Status) line ~width
          | `Target target ->
            let label =
              match target.variant with
              | None -> target.suite
              | Some variant -> "  " ^ variant
            in
            let prefix = if selected then "› " else "  " in
            Tile_text.row (if selected then Pending else Status) (prefix ^ label) ~width)
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

let entry ?(targets = []) ?(status_first = false) lines =
  View_registry.Entry.install ~placement:Band adapter
    { lines; targets; status_first; view = Selection.empty; intents = []; selection_stale = false }
;;
