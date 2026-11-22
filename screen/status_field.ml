open! Core

module Id = struct
  type t =
    | Mode
    | Filename
    | Dirty
    | Pending
    | Position
    | Message
    | Instance
    | Silver_connection
    | Silver_target
  [@@deriving sexp_of, equal, enumerate]
end

module Silver = struct
  type binding =
    { project_root : string
    ; endpoint : string
    }
  [@@deriving equal]

  type t =
    | Disconnected
    | Connecting of binding option
    | Connected of binding
    | Failed of binding option
  [@@deriving equal]
end

type fit =
  | Whole
  | Cut_left
  | Cut_right
[@@deriving sexp_of]

type side =
  | Left
  | Right
[@@deriving sexp_of]

type t =
  { id : Id.t
  ; spans : Span.t list
  ; priority : int
  ; fit : fit
  ; side : side
  }
[@@deriving sexp_of]
