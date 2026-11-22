open! Core
open Cobalt_screen
module Tile = Silver_kickoff_tile

type t =
  { presentation : unit -> Tile.Presentation.t
  ; dispatch : Tile.Intent.t -> unit
  }

let entry = function
  | Some host -> Tile.entry (host.presentation ())
  | None ->
    View_registry.Entry.unavailable Tile.id ~title:Tile.title
      ~notice:"Silver flow kickoff unavailable; use an adapter-enabled build"
;;

let synchronize ui host =
  let presentation = host.presentation () in
  Ui_state.map_view ui Tile.key ~f:(fun tile -> Tile.with_presentation tile presentation)
;;

let dispatch ui host =
  match View_registry.find (Ui_state.views ui) Tile.key with
  | None -> ui
  | Some tile ->
    let tile, intents = Tile.take_intents tile in
    if List.is_empty intents
    then ui
    else (
      List.iter intents ~f:host.dispatch;
      synchronize (Ui_state.map_view ui Tile.key ~f:(fun _ -> tile)) host)
;;
