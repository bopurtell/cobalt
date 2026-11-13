(** The command palette as a minor view: the {!Cobalt_palette.Palette} state for the view
    that opened it, a viewport over its ranked results, and the keys, rows, and cursor
    that present it on the shared host ({!Cobalt_tile.Spec.text_input}). It runs nothing:
    {!Ui_state} accepts it and dispatches the command through the controller, as its key
    binding would. It exists only while open and focused; closing discards the query.

    Content rows: the query prompt, then one result per row with its matched title
    letters highlighted and its shortcut, derived from the active bindings, on the
    right. *)

open! Core
open Cobalt_input
open Cobalt_palette

val id : Cobalt_tile.View_id.t
val spec : Cobalt_tile.Spec.t

type t [@@deriving sexp_of]

(** An open palette over [catalog] for [token], the view a command will apply to.
    [bindings] are the active Normal bindings ({!Bindings.to_list}), for shortcuts.
    [shortcuts] are keys for entries that no binding runs, such as a focused view's
    local commands; they take precedence. *)
val create
  :  ?shortcuts:(Catalog.Id.t * Key.t list) list
  -> Catalog.t
  -> Catalog.Context.t
  -> token:Cobalt_tile.View_id.t
  -> bindings:(Key.t list * Bindings.Target.t) list
  -> t

val palette : t -> Cobalt_tile.View_id.t Palette.t

(** The viewport over results: the palette's selection and the first visible row. *)
val view : t -> Catalog.Id.t Cobalt_tile.Navigation.Selection.t

(** Keep the selected result within a content area [rows] tall (the query takes the
    first row). Never changes the query or which command is selected. *)
val fit : t -> rows:int -> t

type action =
  | Event of Palette.Event.t
  | Accept
[@@deriving sexp_of]

(** Characters, including Space and [j]/[k], edit the query; Backspace deletes a
    character, and Ctrl-w or Ctrl-h (most terminals' Ctrl-Backspace) a word;
    Tab/Ctrl-n and Shift-Tab/Ctrl-p select the next and previous result; Enter
    accepts. Escape and Ctrl-c are the host's ({!Cobalt_tile.Host.key}). *)
val interpret : Key.t list -> action Cobalt_tile.Content_key.t

val hint : string

(** Apply [event], then {!fit} to [rows]. *)
val update : t -> rows:int -> Palette.Event.t -> t

(** The text-entry point after the query on the prompt row, in a [width]-cell content
    area: a bar, always within the area when [width > 0]. *)
val cursor : t -> width:int -> Cobalt_tile.Cursor.t

(** Shell content for a [width] by [rows] content viewport. Control hints default
    to hidden; counts and notices remain visible. *)
val render : ?hotkey_hints:bool -> ?notice:string -> t -> width:int -> rows:int -> Tile_shell.Content.t
