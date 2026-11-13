open! Core

type t [@@deriving sexp_of]
val id : Cobalt_tile.View_id.t
val spec : Cobalt_tile.Spec.t
val create : Cobalt_error.Language_query.target list -> t
(** Change the result heading without resetting query, selection, or scrolling.
    Rendered headings and default footers include matching/total counts. *)
val with_title : t -> string -> t
(** Exact original target, including both ranges and encoding. Selection identity
    is its original list index, allowing identical labels and duplicate targets. *)
val selected : t -> Cobalt_error.Language_query.target option
val selected_identity : t -> int option
val with_preview : t -> Cobalt_navigation_preview_model.Model.state option -> t
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
