open! Core
open Cobalt_input
module Navigation = Cobalt_tile.Navigation
module Selection = Navigation.Selection

let id = Cobalt_tile.View_id.of_string "silver-stage"
let title = "Silver: Stage checklist"
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

module Row = struct
  type t = { id : string; label : string; action : Action.t } [@@deriving sexp_of]
end

module Snapshot = struct
  type t =
    { rows : Row.t list
    ; empty : string
    ; aliases : (Alias.t * Action.t) list
    }
  [@@deriving sexp_of]

  let unavailable reason = { rows = []; empty = reason; aliases = [] }

  let alias t alias =
    List.Assoc.find t.aliases alias ~equal:Alias.equal
    |> Option.value ~default:(Action.Blocked t.empty)
  ;;
end

type t =
  { snapshot : Snapshot.t
  ; view : string Selection.t
  ; intents : Intent.t list
  ; selection_stale : bool
  }
[@@deriving sexp_of]

let key = Type_equal.Id.create ~name:"silver-stage" sexp_of_t
let enqueue t intent = { t with intents = intent :: t.intents }
let take_intents t = { t with intents = [] }, List.rev t.intents
let ids t = List.map t.snapshot.rows ~f:(fun row -> row.id)
let fit t ~rows = { t with view = Selection.fit t.view (ids t) ~equal:String.equal ~rows }

let row t id = List.find t.snapshot.rows ~f:(fun row -> String.equal row.id id)
let selected_row t = Option.bind t.view.selected ~f:(row t)

let with_snapshot t snapshot =
  let next = { t with snapshot } in
  let selection_stale =
    t.selection_stale
    || Option.exists (selected_row t) ~f:(fun previous ->
      match previous.action, row next previous.id with
       (* New dispatch tokens for the same selection do not move or stale it. *)
       | Ready before, Some { action = Ready after; _ } ->
         not (String.equal before.selection after.selection)
      | Ready _, _ -> true
      | Blocked _, _ -> false)
  in
  { next with selection_stale }
;;

type action = Move of Navigation.Motion.t | Run

let run_key = Key.char 'R'

let interpret _ = function
  | [ key ] when Key.equal key run_key -> Cobalt_tile.Content_key.Action Run
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
  ; hint = "Silver stage checklist: j/k select, R runs through the selected stage, Escape returns"
  ; perform = (fun t controller ~context:_ ~rows ~width:_ action ->
      let t = fit t ~rows in
      let done_ t = t, View_registry.Outcome.create controller in
      let blocked reason =
        t, View_registry.Outcome.create controller ~notice:(`Post (reason ^ "; nothing ran"))
      in
      match action with
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
      :: Navigation.commands)
  ; signal = (fun _ _ -> None)
  ; label = (fun _ -> None)
  ; text_area = (fun _ ~rows:_ ~width:_ -> None)
  ; render = (fun t _ ~hotkey_hints ~focused ~notice ~pending ~width ~rows ->
      let body =
        match t.snapshot.rows with
        | [] when rows > 0 -> [ Tile_text.row Status t.snapshot.empty ~width ]
        | rows_data ->
          let view = (fit t ~rows).view in
          let top = if focused then view.top else 0 in
          List.take (List.drop rows_data top) (Int.max 0 rows)
          |> List.map ~f:(fun row ->
            let selected = focused && Option.exists view.selected ~f:(String.equal row.id) in
            let prefix = if selected then "› " else "  " in
            let detail =
              match row.action with
              | Ready _ when selected && t.selection_stale -> "Reselect stage"
              | Ready intent -> "Ready: " ^ intent.summary
              | Blocked reason -> "Unavailable: " ^ reason
            in
            Tile_text.row (if selected then Pending else Status)
              (prefix ^ row.label ^ " · " ^ detail) ~width)
      in
      let default = if focused || hotkey_hints then "j/k select | R run through stage | Esc" else "" in
      { title; body; footer = Some (Tile_shell.Label.footer ~notice ~pending ~default) })
  }
;;

let entry snapshot =
  View_registry.Entry.install adapter
    { snapshot; view = Selection.empty; intents = []; selection_stale = false }
;;
