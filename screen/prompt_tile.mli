(** A registered view's text-input float, opened over that view, which is
    neither left nor changed meanwhile. It hosts a single-line prompt
    ({!View_registry.Ask.Prompt}) or a form ({!View_registry.Ask.Form}) that
    edits one field at a time. Its input edits
    like the palette's query ({!Cobalt_palette.Query}: typed and pasted text is
    sanitized to one line). The view's validation runs on every edit once the text
    has been edited, or when Enter is refused; its error shows on the row under the
    input. Enter accepts valid text; Escape, Tab and Ctrl-c cancel ({!Ui_state} routes
    them). On a form Tab instead advances fields, and Enter applies them
    together. Closing returns focus to the view. *)

open! Core
open Cobalt_input

val id : Cobalt_tile.View_id.t
val spec : Cobalt_tile.Spec.t

type t [@@deriving sexp_of]

(** [validate] gives [Some error] for text that cannot be accepted. *)
val create
  :  origin:Cobalt_tile.View_id.t
  -> title:string
  -> initial:string
  -> validate:(string -> string option)
  -> t

val create_form
  :  origin:Cobalt_tile.View_id.t
  -> title:string
  -> fields:(string * string) list
  -> t

(** The view that asked, and that focus returns to. *)
val origin : t -> Cobalt_tile.View_id.t
val is_form : t -> bool

val title : t -> string
val text : t -> string

(** The validation error on display, if any. *)
val error : t -> string option

val preferred_size : Floating.Size.t

(** The smallest outer size: a frame, the input and the error row. *)
val minimum : Floating.Size.t

module Event : sig
  type t =
    | Insert of Uchar.t
    | Paste of string
    | Backspace
    | Delete_word
    | Clear
    | Field of int
  [@@deriving sexp_of]
end

type action =
  | Edit of Event.t
  | Accept
[@@deriving sexp_of]

(** Characters, including Space, [?] and [q], are text; Backspace deletes a
    character, and Ctrl-w or Ctrl-h a word; Enter accepts. *)
val interpret : t -> Key.t list -> action Cobalt_tile.Content_key.t

val hint : t -> string
val update : t -> Event.t -> t

(** The validated text or the atomic form draft; otherwise the prompt with its error. *)
val accept : t -> (View_registry.Answer.t, t) Result.t

(** The text-entry point after the input, in a [width]-cell content area. *)
val cursor : t -> width:int -> Cobalt_tile.Cursor.t

(** Shell content for a [width] by [rows] content viewport. Control hints default to
    hidden; notices remain visible. *)
val render : ?hotkey_hints:bool -> ?notice:string -> t -> width:int -> rows:int -> Tile_shell.Content.t
