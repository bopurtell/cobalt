(** Prepared, source-shaped presentation data. No provider code is called here.
    Preparation belongs at the composition boundary, never in [Frame.render]. *)

open! Core

type t

(** Atomically validate screen geometry against the actual immutable buffer.
    Milestone 1 deliberately accepts only one positive-width Plain source scalar
    replaced by one positive-width Plain display scalar of the same cell width.
    BOTH source and replacement must belong to this conservative grapheme-safe
    scalar allowlist (inclusive): printable ASCII U+0020–U+007E; Latin letters
    U+00C0–U+00D6, U+00D8–U+00F6, U+00F8–U+02AF; bullet U+2022;
    box drawing U+2500–U+257F; or CJK unified ideographs U+3400–U+4DBF and
    U+4E00–U+9FFF. BOTH immediate source neighbors on the same line must also
    be allowlisted positive-width Plain scalars; a source line boundary is safe.
    These scalars are GCB Other, not emoji modifier bases or extended pictographs;
    adjacent accepted replacements cannot form emoji, regional-indicator,
    Hangul or Indic clusters. Arbitrary other scalars, including emoji,
    modifiers and positive-width SpacingMarks, are rejected even when cell widths
    match. Tabs, escapes, multiline/multiscalar replacements and unsupported
    source neighbors (including zero-width scalars) are rejected, not silently
    partially applied. Widths and
    safety mapping come exclusively from [Cell_map]; distant source positions
    use the sparse line index, never whole-line glyph arrays.

    Snapshot keys must identify the supplied source version, just as for syntax
    highlights. The prepared value retains [source] as its provenance; rendering
    requires that exact buffer object, not merely equal lengths or revisions.
    Callers should omit decorations after any [Error].

    Rich styles remain source-shaped: no concealment, inserted labels, reflow,
    changed cell widths or whole-row code backgrounds. Only actual source glyphs
    receive roles, not blank EOL padding or unsafe display forms. The conservative
    same-width Replace primitive remains available for synthetic providers. *)
val prepare
  :  source:Cobalt_core.Text_buffer.t
  -> Cobalt_decoration.Snapshot.t
  -> (t, Error.t) Result.t

val key : t -> Cobalt_decoration.Snapshot.Key.t
val matches : t -> Cobalt_decoration.Snapshot.Key.t -> bool
val is_empty : t -> bool

(** O(1) physical provenance check. An independently reconstructed equal buffer
    must be prepared again. This does not establish the host's document identity;
    the independently supplied expected key remains authoritative for that. *)
val matches_source : t -> Cobalt_core.Text_buffer.t -> bool

(** Legacy syntax projection. Accent = Keyword, Literal = String, Muted = Comment.
    Rich roles have meaningful fallback categories, but should normally travel
    separately through [Style.Document.decoration] to preserve existing syntax. *)
val syntax_of_role : Cobalt_decoration.Snapshot.Role.t -> Style.Syntax.t

(** Apply replacements only to an already-windowed array from the prepared source.
    Positions, columns, widths and kinds are preserved, so search and all
    interaction overlays still address original document bytes. [line_start] is
    the document byte offset of the window's source line. No whole-line glyph
    array is created. Call only after the source/key gates and reveal policy.
    With single-scalar replacements a source search hit is never ambiguous. *)
val apply : t -> line_start:int -> Cell_map.Glyph.t array -> Cell_map.Glyph.t array

(** Per-line semantic lookup for a source window. Replacement roles override
    Style operations, which override existing syntax; [None] means retain syntax.
    Escape glyphs are never decorated. Synthetic padding must be excluded by
    the caller. Repeated source positions (split TABs) are supported; backward
    positions safely reset the underlying style cursor. This helper works on
    either original or replaced glyphs. *)
val lookup_from : t -> line_start:int -> (Cell_map.Glyph.t -> Style.Syntax.t option)

(** Same source/replacement precedence and safety rules as [lookup_from], retaining
    the generic role rather than projecting it to syntax. *)
val role_lookup_from
  :  t
  -> line_start:int
  -> (Cell_map.Glyph.t -> Cobalt_decoration.Snapshot.Role.t option)
