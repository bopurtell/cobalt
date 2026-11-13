open! Core
open Cobalt_content_picker
val id : Cobalt_tile.View_id.t
val spec : Cobalt_tile.Spec.t
type 'token t
val create : token:'token -> snapshot:Model.snapshot -> 'token t
val session : 'token t -> 'token Model.t
val view : _ t -> Model.hit Cobalt_tile.Navigation.Selection.t
val fit : _ t -> rows:int -> unit
type action = Event of Cobalt_palette.Palette.Event.t | Accept [@@deriving sexp_of]
val interpret : Cobalt_input.Key.t list -> action Cobalt_tile.Content_key.t
val update : _ t -> rows:int -> Cobalt_palette.Palette.Event.t -> unit
val expect : _ t -> Model.request -> unit
val install : _ t -> Model.snapshot -> bool
val accept : 'token t -> release:(unit -> unit) -> consume:('token Model.intent -> unit) -> unit
val cancel : _ t -> release:(unit -> unit) -> unit
val cursor : _ t -> width:int -> Cobalt_tile.Cursor.t
(** Control hints default to hidden; counts, status and notices remain visible. *)
val render : ?hotkey_hints:bool -> ?notice:string -> _ t -> width:int -> rows:int -> Tile_shell.Content.t
