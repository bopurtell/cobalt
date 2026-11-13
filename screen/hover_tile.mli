open! Core

type t [@@deriving sexp_of]
val id : Cobalt_tile.View_id.t
val spec : Cobalt_tile.Spec.t
(** Captures display text only; no source or host effects. Markdown rendering is
    deliberately lightweight, with literal inline links. Input is capped at
    256 KiB, each line at 4096 bytes, and consecutive zero-width scalars at 16;
    truncation/elision is marked. *)
val create : Cobalt_error.Language_query.hover -> t
val top : t -> int
val fit : t -> width:int -> rows:int -> t
type action = Scroll of Cobalt_tile.Navigation.Motion.t | Close [@@deriving sexp_of]
val interpret : Cobalt_input.Key.t list -> action Cobalt_tile.Content_key.t
val scroll : t -> width:int -> rows:int -> Cobalt_tile.Navigation.Motion.t -> t
(** Cell-based hard wrapping, with at most [rows] body rows. Nonpositive sizes
    are safe. Width is additionally capped at 4096 cells. *)
val render
  :  ?hotkey_hints:bool
  -> ?notice:string
  -> t
  -> width:int
  -> rows:int
  -> Tile_shell.Content.t
