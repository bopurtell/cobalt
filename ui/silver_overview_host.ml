open! Core
open Cobalt_screen
module Tile = Silver_overview_tile
module Field = Tile.Field
module Target = Tile.Target
module Test_action = Tile.Test_action
module Stage = Silver_stage_tile
module Connection = Tile.Connection

type binding =
  { endpoint : string
  ; project_root : string
  ; run : string option
  }

type t =
  { rows : unit -> string list
  ; connection_status : unit -> Status_field.Silver.t
  ; targets : unit -> Target.t list
  ; status_first : unit -> bool
  ; test_action : unit -> Test_action.t
  ; apply_settings : Target.t -> (string * string) list -> (unit, string) result
  ; launch : Target.t -> (string, string) result Async.Deferred.t
  ; stages : unit -> Stage.Snapshot.t
  ; launch_stage : Stage.Intent.t -> (string, string) result Async.Deferred.t
  ; connections : generation:int -> Connection.lookup Async.Deferred.t
  ; connect : Connection.selection -> (string, string) result option Async.Deferred.t
  ; show : unit -> unit
  ; hide : unit -> unit
  ; refresh : unit -> unit
  ; revision : unit -> int
  ; await_change : after:int -> unit Async.Deferred.t
  ; shutdown : unit -> unit
  ; kickoff : Silver_kickoff_host.t option
  }

type factory = (test_default:(string * string option) option -> binding option -> t) option

let entry = function
  | Some t -> Tile.entry ~targets:(t.targets ()) ~status_first:(t.status_first ()) (t.rows ())
  | None ->
    View_registry.Entry.unavailable Tile.id ~title:Tile.title
      ~notice:"Silver overview unavailable; use an adapter-enabled build"
;;

let stage_entry = function
  | Some t -> Stage.entry (t.stages ())
  | None ->
    View_registry.Entry.unavailable Stage.id ~title:Stage.title ~notice:Stage.adapter_unavailable
;;

let synchronize ui (t : t) =
  let ui = Ui_state.with_silver_status ui (Some (t.connection_status ())) in
  let ui = Ui_state.with_silver_stage ui (t.stages ()) in
  let ui = Ui_state.with_silver_test
     (Ui_state.map_view ui Tile.key ~f:(fun tile ->
        let tile = Tile.with_rows tile (t.rows ()) in
        let tile = Tile.with_targets tile (t.targets ()) in
        Tile.with_status_first tile (t.status_first ())))
     (t.test_action ())
  in
  Option.value_map t.kickoff ~default:ui ~f:(Silver_kickoff_host.synchronize ui)
;;

let take_stage_intents ui =
  match View_registry.find (Ui_state.views ui) Stage.key with
  | None -> ui, []
  | Some tile ->
    let tile, intents = Stage.take_intents tile in
    if List.is_empty intents then ui, []
    else Ui_state.map_view ui Stage.key ~f:(fun _ -> tile), intents
;;

let take_intents ui =
  match View_registry.find (Ui_state.views ui) Tile.key with
  | None -> ui, []
  | Some tile ->
    let tile, intents = Tile.take_intents tile in
    if List.is_empty intents then ui, []
    else Ui_state.map_view ui Tile.key ~f:(fun _ -> tile), intents
;;
