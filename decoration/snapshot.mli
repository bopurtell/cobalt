open! Core

module Role : sig
  (** Generic document semantics, independent of any provider/parser. Declaration
      order is the stable tie-breaker for equally sized overlapping Style ranges;
      the original Accent/Literal/Muted ordering and meaning are unchanged. *)
  type t =
    | Accent | Literal | Muted
    | Heading_1 | Heading_2 | Heading_3 | Heading_4 | Heading_5 | Heading_6
    | Emphasis | Strong | Code_inline | Code_block | Link | Link_destination
    | Quote | List_marker | Checkbox
  [@@deriving sexp_of, equal, compare]
end

module Document_id : sig
  type t
  val create : unit -> t
end

module Key : sig
  type t
  (** [provider] includes its version; [configuration] includes its generation.
      Keys must identify an immutable source version, including after reload/undo. *)
  val create : document:Document_id.t -> revision:int -> provider:string -> configuration:string -> t
  val equal : t -> t -> bool
  val same_document : t -> t -> bool
  val revision : t -> int
  val provider : t -> string
  val configuration : t -> string
end

module Range : sig
  (** Half-open document-wide UTF-8 source-byte offsets. *)
  type t = { start : int; stop : int } [@@deriving sexp_of, equal, compare]
end

module Operation : sig
  type t =
    | Style of { range : Range.t; role : Role.t }
    | Replace of { range : Range.t; text : string; role : Role.t option }
  [@@deriving sexp_of, equal]

  val range : t -> Range.t
  val compare : t -> t -> int
end

module Limits : sig
  type t =
    { max_source_bytes : int
    ; max_operations : int
    ; max_replacement_bytes : int
    ; max_total_replacement_bytes : int
    }
  [@@deriving sexp_of]

  (** 16 MiB source, 4096 operations, 4096 bytes per replacement, 65536 total
      replacement bytes. All limits must be nonnegative. *)
  val default : t
end

type t

(** Atomic validation: valid UTF-8 source/text, nonempty in-bounds ranges at
    scalar boundaries, no overlapping replacements (even identical duplicates),
    and bounded input/output sizes. Replaced source ranges cannot contain LF;
    replacement text cannot contain C0/C1 controls, including LF, TAB and ESC.
    Styles may span lines and overlap replacements.

    Operations are sorted by range start, stop, then Style before Replace, then
    role/text. Duplicates of styles are retained. Style lookup chooses the
     shortest covering Style range, then Role declaration order,
    then ascending start/stop. Input order never changes precedence.

    No source bytes are retained. Keys are authoritative for freshness.
    Width preservation and combining/context safety are the adapter's job.
    In particular, the initial screen adapter only supports a single source
    scalar replaced by a single scalar of equal positive cell width. Both
    endpoints and any immediate same-line source neighbors must belong to its
    conservative context-free subset: printable ASCII, Latin letters
    U+00C0..00D6/U+00D8..00F6/U+00F8..02AF, bullet U+2022, box drawing
    U+2500..257F, and CJK unified U+3400..4DBF/U+4E00..9FFF. Arbitrary equal-width
    scalars are not supported; the adapter also retains its safety/zero-width
    context checks. The pure model permits bounded multiscalar and empty
    replacement text; successful model validation alone does not authorize
    drawing replacements.
    Size budgets are checked before building indexes or scanning UTF-8. *)
val create
  :  ?limits:Limits.t
  -> key:Key.t
  -> source:string
  -> Operation.t list
  -> (t, Error.t) Result.t

val key : t -> Key.t
val matches : t -> Key.t -> bool
val operations : t -> Operation.t list
val is_empty : t -> bool
val source_length : t -> int

(** Original operations intersecting [start, stop), not clipped, in deterministic
    order. Empty/reversed queries return []; out-of-bounds queries are safe.
    Uses an immutable augmented interval index, not a full operation scan. *)
val intersecting : t -> start:int -> stop:int -> Operation.t list

(** O(log n) lookup of Style operations only. Shortest covering range wins,
     followed by Role declaration order, then ascending start/stop.
    Gaps and out-of-bounds offsets return [None].

    Replacement roles remain attached to their operations: the adapter applies
    [Some role] only to the replaced source scalar, overriding this Style lookup;
    [None] preserves the Style role or underlying syntax when no Style applies.
    A replacement role must not leak onto neighboring source scalars. *)
val style_at : t -> int -> Role.t option

(** Alias of [style_at], with identical Style-only precedence and semantics. *)
val role_at : t -> int -> Role.t option

(** Per-line Style cursor: O(log n) initialization, then amortized O(1) for
    monotonic offsets plus crossed style spans. Backward offsets reset safely. *)
val lookup_from : t -> int -> (int -> Role.t option)
