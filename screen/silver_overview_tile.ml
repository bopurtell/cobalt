open! Core
open Cobalt_input
module Navigation = Cobalt_tile.Navigation

let id = Cobalt_tile.View_id.of_string "silver-overview"
let title = "Silver overview"
let spec = Cobalt_tile.Spec.read_only id ~title

module Intent = struct
  type t = Refresh [@@deriving sexp_of, equal]
end

type t =
  { lines : string list
  ; top : int
  ; intent : Intent.t option
  }
[@@deriving sexp_of]

let with_rows t lines = { t with lines }
let take_intent t = { t with intent = None }, t.intent
let key = Type_equal.Id.create ~name:"silver-overview" sexp_of_t
let max_top t ~rows = Int.max 0 (List.length t.lines - Int.max 1 rows)
let fit t ~rows = { t with top = Int.min t.top (max_top t ~rows) }

type action =
  | Move of Navigation.Motion.t
  | Refresh

let refresh = Key.char 'r'
let interpret _ = function
  | [ key ] when Key.equal key refresh -> Cobalt_tile.Content_key.Action Refresh
  | keys -> Cobalt_tile.Content_key.map (Navigation.interpret keys) ~f:(fun move -> Move move)
;;

let adapter : (t, action) View_registry.Adapter.t =
  { spec
  ; key
  ; fit = (fun t _ ~rows ~width:_ -> fit t ~rows)
  ; leave = (fun t -> { t with top = 0 })
  ; text_view = (fun _ -> None)
  ; interpret
  ; escape = (fun _ -> None)
  ; hint = "Read-only Silver overview: j/k scroll, r refresh, Escape returns"
  ; perform = (fun t controller ~context:_ ~rows ~width:_ action ->
      let t =
        match action with
        | Refresh -> { t with intent = Some Intent.Refresh }
        | Move motion ->
          let top = Navigation.move_offset t.top ~total:(List.length t.lines) ~rows motion in
          { t with top }
      in
      t, View_registry.Outcome.create controller)
  ; commands = (fun _ ->
      Cobalt_tile.Local_command.create "refresh" ~keys:[ refresh ] "Refresh Silver overview"
      :: Navigation.commands)
  ; signal = (fun _ _ -> None)
  ; label = (fun _ -> None)
  ; text_area = (fun _ ~rows:_ ~width:_ -> None)
  ; render = (fun t _ ~hotkey_hints ~focused ~notice ~pending ~width ~rows ->
      let top = if focused then (fit t ~rows).top else 0 in
      let body =
        List.take (List.drop t.lines top) (Int.max 0 rows)
        |> List.map ~f:(Tile_text.row Status ~width)
      in
      let default =
        if not hotkey_hints then ""
        else if focused then "j/k r Esc | Space v S: close"
        else "Space v U: focus; v S: close"
      in
      { title; body; footer = Some (Tile_shell.Label.footer ~notice ~pending ~default) })
  }
;;

let entry lines =
  View_registry.Entry.install ~placement:Band adapter { lines; top = 0; intent = None }
;;
