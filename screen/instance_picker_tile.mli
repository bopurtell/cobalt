open! Core

(** Pure hierarchy-path picker. Selection returns the exact captured instance;
    activation and navigation belong to the host. The active path is marked in
    the list independently of the keyboard selection. *)
type t [@@deriving sexp_of]

val id : Cobalt_tile.View_id.t
val spec : Cobalt_tile.Spec.t
val create
  :  module_name:string
  -> active:string option
  -> Cobalt_error.Language_query.instance list
  -> t
val selected : t -> Cobalt_error.Language_query.instance option
val query : t -> string
val fit : t -> rows:int -> t
val interpret : Cobalt_input.Key.t list -> Palette_tile.action Cobalt_tile.Content_key.t
val update : t -> rows:int -> Cobalt_palette.Palette.Event.t -> t
val cursor : t -> width:int -> Cobalt_tile.Cursor.t
val render
  :  ?hotkey_hints:bool
  -> ?notice:string
  -> t
  -> width:int
  -> rows:int
  -> Tile_shell.Content.t
