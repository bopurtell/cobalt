(** Current-document adapter, registered in the shared transient float host. Host must validate
    on current-controller changes and before rendering, schedule/yield work, and
    install successful acceptance's controller. Requires three content rows. *)
open! Core
type t
val id : Cobalt_tile.View_id.t
val spec : Cobalt_tile.Spec.t
val create : Cobalt_app.Controller.t -> t
val session : t -> Cobalt_line_picker.Lines.t
val fit : t -> rows:int -> unit
val interpret : Cobalt_input.Key.t list -> File_picker_tile.action Cobalt_tile.Content_key.t
val update : t -> rows:int -> Cobalt_palette.Palette.Event.t -> unit
val work : t -> budget:int -> unit
val validate : t -> Cobalt_app.Controller.t -> bool
val accept : t -> current:(unit -> Cobalt_app.Controller.t) -> release:(unit -> unit)
  -> Cobalt_app.Controller.t option Or_error.t
val cancel : t -> release:(unit -> unit) -> unit
val cursor : t -> width:int -> Cobalt_tile.Cursor.t
(** Control hints default to hidden; counts, status and notices remain visible. *)
val render : ?hotkey_hints:bool -> ?notice:string -> t -> width:int -> rows:int -> Tile_shell.Content.t
