open! Core

(** A feature-local, lazily initialized owner of native block/inline parsers.
    No source, tree, or previous snapshot is retained between calls. *)
type t

val create : unit -> t
val close : t -> unit

(** Stable grammar/configuration identity, suitable for host cache keys. *)
val configuration : string

val key
  :  t
  -> document:Cobalt_decoration.Snapshot.Document_id.t
  -> revision:int
  -> Cobalt_decoration.Snapshot.Key.t

(** Atomic, bounded source-only styling. An error never returns partial/stale
    output. A closed provider rejects decoration. Only [.md] and [.markdown],
    compared ASCII-case-insensitively, are eligible; the host owns eligibility,
    revision/cache invalidation, cursor and resize policy.

    Fixed per-decoration budgets: 256 KiB source, 4096 physical lines,
    4096 style operations, 65536 visited syntax nodes, depth 1024,
    4096 inline parses, 8192 included-range fragments, and a 100 ms native
    parsing deadline (best-effort tree-sitter timeout).
    Limits reject the complete result, never silently truncate it. *)
val decorate
  :  t
  -> key:Cobalt_decoration.Snapshot.Key.t
  -> source:string
  -> (Cobalt_decoration.Snapshot.t, Error.t) Result.t

(** Number of actual native block parses attempted, including failed parses.
    Validation failures before entering native code do not increment it. *)
val parse_count : t -> int

(** Number of actual included-range inline parses attempted. *)
val inline_parse_count : t -> int

val eligible_path : string option -> bool
