open! Core
open Cobalt_screen
module Tile = Silver_overview_tile

type binding =
  { endpoint : string
  ; project_root : string
  ; run : string
  }

type t =
  { rows : unit -> string list
  ; show : unit -> unit
  ; hide : unit -> unit
  ; refresh : unit -> unit
  ; revision : unit -> int
  ; await_change : after:int -> unit Async.Deferred.t
  ; shutdown : unit -> unit
  }

type factory = (binding -> t) option

let entry = function
  | Some t -> Tile.entry (t.rows ())
  | None ->
    View_registry.Entry.unavailable Tile.id ~title:Tile.title
      ~notice:"Silver overview unavailable; use an adapter-enabled build and bind it at startup"
;;

let take_intent ui =
  match View_registry.find (Ui_state.views ui) Tile.key with
  | None -> ui, None
  | Some tile ->
    let tile, intent = Tile.take_intent tile in
    if Option.is_none intent then ui, None
    else Ui_state.map_view ui Tile.key ~f:(fun _ -> tile), intent
;;
