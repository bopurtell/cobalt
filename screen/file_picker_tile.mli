open! Core
open Cobalt_file_picker

(** Shared floating adapter, assembled explicitly through Ui_state (no binding).
    Host owns discovery polling, yielding work turns, capture and focus. Content
    reserves query/status rows, then results; root is in title and errors/limits
    also in footer. Tiny content areas may clip status; the host sets minimum sizes. *)
val id : Cobalt_tile.View_id.t
val spec : Cobalt_tile.Spec.t
type 'token t
val create : token:'token -> discovery:Model.Discovery.t -> 'token t
val session : 'token t -> 'token Interaction.t
val view : _ t -> Model.Candidate.Id.t Cobalt_tile.Navigation.Selection.t
val preview : _ t -> Cobalt_file_preview_model.Model.snapshot option
val visible_stamp : _ t -> int * int * int
val expect_preview : _ t -> Cobalt_file_preview_model.Model.request option -> unit
val clear_preview : _ t -> unit
val install_preview : _ t -> Cobalt_file_preview_model.Model.snapshot -> bool
val columns : width:int -> int * int option
val fit : _ t -> rows:int -> unit
type action = Event of Cobalt_palette.Palette.Event.t | Accept [@@deriving sexp_of]
(** Tab/Shift-Tab and Ctrl-n/p navigate results. Escape and Ctrl-c remain
    host-owned. Paste is delivered as an Event. *)
val interpret : Cobalt_input.Key.t list -> action Cobalt_tile.Content_key.t
val update : _ t -> rows:int -> Cobalt_palette.Palette.Event.t -> unit
val install : _ t -> Model.Discovery.t -> bool
val install_update : _ t -> Model.Discovery.Update.t -> bool
val work : _ t -> budget:int -> unit
val accept : 'token t -> release:(unit -> unit) -> consume:('token Model.Request.t -> unit) -> unit
val cancel : _ t -> release:(unit -> unit) -> unit
val cursor : _ t -> width:int -> Cobalt_tile.Cursor.t
(** Control hints default to hidden; counts, status and notices remain visible. *)
val render : ?hotkey_hints:bool -> ?notice:string -> _ t -> width:int -> rows:int -> Tile_shell.Content.t
