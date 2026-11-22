open! Core
open Cobalt_screen
module Tile = Silver_kickoff_tile

type t =
  { presentation : unit -> Tile.Presentation.t
  ; dispatch : Tile.Intent.t -> bool
  }

let entry = function
  | Some host -> Tile.entry (host.presentation ())
  | None ->
    View_registry.Entry.unavailable Tile.id ~title:Tile.title
      ~notice:"Silver flow kickoff unavailable; use an adapter-enabled build"
;;

let review_entry = function
  | Some host -> Tile.review_entry (host.presentation ())
  | None ->
    View_registry.Entry.unavailable Tile.review_id ~title:Tile.review_title
      ~notice:"Silver flow kickoff unavailable; use an adapter-enabled build"
;;

let synchronize ui host =
  let presentation = host.presentation () in
  let ui = Ui_state.map_view ui Tile.key ~f:(fun tile -> Tile.with_presentation tile presentation) in
  Ui_state.map_view ui Tile.review_key ~f:(fun tile -> Tile.with_review_presentation tile presentation)
;;

let dispatch ui host ~stages =
  let take ui key =
    match View_registry.find (Ui_state.views ui) key with
    | None -> ui, []
    | Some tile ->
      let tile, intents = Tile.take_intents tile in
      if List.is_empty intents then ui, []
      else Ui_state.map_view ui key ~f:(fun _ -> tile), intents
  in
  let ui, choices = take ui Tile.key in
  let ui, review = take ui Tile.review_key in
  match choices @ review with
  | [] -> ui
  | intents ->
    let flow_selected =
      List.fold intents ~init:false ~f:(fun changed intent -> host.dispatch intent || changed)
    in
    let ui = synchronize ui host in
    let update = if flow_selected then Ui_state.with_selected_silver_flow else Ui_state.with_silver_stage in
    update ui (stages ())
;;
