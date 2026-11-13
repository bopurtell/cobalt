(** The [?] help float: a read-only list of the local commands that a registered
    view ({!View_registry}) declares in its current state, with their keys, or of
    the keys of the popup float ({!Popup_tile}) it opens over. It runs nothing. It
    opens on the single float slot over the view (or popup) it describes, which is
    neither left nor changed meanwhile; closing it ([q], [?], Escape, or Tab) returns
    focus there. *)

open! Core

val id : Cobalt_tile.View_id.t
val spec : Cobalt_tile.Spec.t

type t [@@deriving sexp_of]

(** Help for [origin], whose title is [title]. *)
val create : origin:Cobalt_tile.View_id.t -> title:string -> Cobalt_tile.Local_command.t list -> t

(** Help listing [(keys, description)] rows as given, e.g. a popup's
    ({!Cobalt_vcs.Popup.help}: [("-n", "Disable hooks (--no-verify)")]). *)
val of_entries : origin:Cobalt_tile.View_id.t -> title:string -> (string * string) list -> t

(** The view (or popup float) that focus returns to. *)
val origin : t -> Cobalt_tile.View_id.t

(** The commands given to {!create}; empty for {!of_entries}. *)
val commands : t -> Cobalt_tile.Local_command.t list

(** The first visible command. *)
val top : t -> int

(** Outer size that shows every command when the screen allows. *)
val preferred_size : t -> Floating.Size.t

type action =
  | Scroll of Cobalt_tile.Navigation.Motion.t
  | Close
[@@deriving sexp_of]

(** The shared list motions scroll; [q] and [?] close. *)
val interpret : Cobalt_input.Key.t list -> action Cobalt_tile.Content_key.t

val hint : string

(** Scroll within a content viewport [rows] tall. *)
val scroll : t -> rows:int -> Cobalt_tile.Navigation.Motion.t -> t

(** Shell content for a [width] by [rows] content viewport: one command per row, its
    keys in a column before its description. Key hints default to hidden; notices
    remain visible. *)
val render : ?hotkey_hints:bool -> ?notice:string -> t -> width:int -> rows:int -> Tile_shell.Content.t
