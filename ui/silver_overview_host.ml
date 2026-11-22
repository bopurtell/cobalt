open! Core
open Cobalt_screen
module Tile = Silver_overview_tile
module Field = Tile.Field
module Target = Tile.Target
module Test_action = Tile.Test_action

type binding =
  { endpoint : string
  ; project_root : string
  ; run : string option
  }

type t =
  { rows : unit -> string list
  ; targets : unit -> Target.t list
  ; status_first : unit -> bool
  ; test_action : unit -> Test_action.t
  ; apply_settings : Target.t -> (string * string) list -> (unit, string) result
  ; launch : Target.t -> (string, string) result Async.Deferred.t
  ; connections : unit -> string list Async.Deferred.t
  ; connect : binding -> (unit, string) result Async.Deferred.t
  ; show : unit -> unit
  ; hide : unit -> unit
  ; refresh : unit -> unit
  ; revision : unit -> int
  ; await_change : after:int -> unit Async.Deferred.t
  ; shutdown : unit -> unit
  }

type factory = (test_default:(string * string option) option -> binding option -> t) option

let entry = function
  | Some t -> Tile.entry ~targets:(t.targets ()) ~status_first:(t.status_first ()) (t.rows ())
  | None ->
    View_registry.Entry.unavailable Tile.id ~title:Tile.title
      ~notice:"Silver overview unavailable; use an adapter-enabled build"
;;

let synchronize ui (t : t) =
  Ui_state.with_silver_test
     (Ui_state.map_view ui Tile.key ~f:(fun tile ->
        let tile = Tile.with_rows tile (t.rows ()) in
        let tile = Tile.with_targets tile (t.targets ()) in
        Tile.with_status_first tile (t.status_first ())))
    (t.test_action ())
;;

let take_intents ui =
  match View_registry.find (Ui_state.views ui) Tile.key with
  | None -> ui, []
  | Some tile ->
    let tile, intents = Tile.take_intents tile in
    if List.is_empty intents then ui, []
    else Ui_state.map_view ui Tile.key ~f:(fun _ -> tile), intents
;;
