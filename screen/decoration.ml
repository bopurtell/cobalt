open! Core
open Cobalt_core

module Snapshot = Cobalt_decoration.Snapshot

type replacement =
  { range : Snapshot.Range.t
  ; col : int
  ; width : int
  ; source_text : string
  ; text : string
  ; role : Snapshot.Role.t option
  }

type t =
  { snapshot : Snapshot.t
  ; source : Text_buffer.t
  ; replacements : replacement array
  }

let key t = Snapshot.key t.snapshot
let matches t key = Snapshot.matches t.snapshot key
let is_empty t = Snapshot.is_empty t.snapshot
let matches_source t source = phys_equal t.source source

let syntax_of_role = function
  | Snapshot.Role.Accent -> Style.Syntax.Keyword
  | Literal -> Style.Syntax.String
  | Muted -> Style.Syntax.Comment
;;

(* Width equality alone does not prevent new grapheme clusters (emoji modifiers,
   regional indicators, Hangul/Indic sequences). Both substitution endpoints and
   their immediate same-line source neighbors must be GCB Other and neither
   emoji modifier bases nor extended pictographs. This intentionally small scalar
   allowlist has those properties, without introducing a second Unicode database
   or changing Cell_map's width/safety authority. *)
let context_free_scalar text =
  let decode = Stdlib.String.get_utf_8_uchar text 0 in
  let scalar = Uchar.to_scalar (Stdlib.Uchar.utf_decode_uchar decode) in
  (scalar >= 0x20 && scalar <= 0x7e)
  || (scalar >= 0xc0 && scalar <= 0xd6)
  || (scalar >= 0xd8 && scalar <= 0xf6)
  || (scalar >= 0xf8 && scalar <= 0x2af)
  || scalar = 0x2022
  || (scalar >= 0x2500 && scalar <= 0x257f)
  || (scalar >= 0x3400 && scalar <= 0x4dbf)
  || (scalar >= 0x4e00 && scalar <= 0x9fff)
;;

let single_plain text =
  match Cell_map.glyphs text with
  | [| glyph |]
    when Cell_map.Kind.equal glyph.kind Plain && glyph.width > 0
         && context_free_scalar text ->
    Some glyph
  | _ -> None
;;

let allowed_context_at source offset =
  let stop = Option.value_exn (Text_buffer.next_boundary source offset) in
  Option.is_some
    (single_plain (Text_buffer.slice source ~pos:offset ~len:(stop - offset)))
;;

let prepare ~source snapshot =
  if Snapshot.source_length snapshot <> Text_buffer.length source
  then Or_error.error_string "Decoration source length does not match snapshot"
  else if List.exists (Snapshot.operations snapshot) ~f:(fun operation ->
    let range = Snapshot.Operation.range operation in
    range.start >= range.stop
    || not (Text_buffer.is_boundary source range.start)
    || not (Text_buffer.is_boundary source range.stop))
  then Or_error.error_string "Decoration ranges do not match source scalar boundaries"
  else
    let prepare_replacement range text role =
      let open Or_error.Let_syntax in
      let start = range.Snapshot.Range.start and stop = range.stop in
      if not (Text_buffer.is_boundary source start && Text_buffer.is_boundary source stop)
         || start >= stop
      then Or_error.error_string "Decoration source range is not a scalar boundary"
      else
        let line = Text_buffer.line_of_offset source start in
        if stop > Text_buffer.line_end source line
           || not (Option.equal Int.equal (Text_buffer.next_boundary source start) (Some stop))
        then Or_error.error_string "Decoration replacements require one source scalar on one line"
        else
          let source_text = Text_buffer.slice source ~pos:start ~len:(stop - start) in
          let%bind original =
            Option.value_map (single_plain source_text)
              ~default:(Or_error.error_string "Decoration source scalar is not an allowlisted safe positive-width glyph")
              ~f:Or_error.return
          in
          let%bind display =
            Option.value_map (single_plain text)
              ~default:(Or_error.error_string "Decoration display text is not one allowlisted safe positive-width glyph")
              ~f:Or_error.return
          in
          let previous_safe =
            match Text_buffer.prev_boundary source start with
            | Some previous when previous >= Text_buffer.line_start source line ->
              allowed_context_at source previous
            | Some _ | None -> true
          in
          if not previous_safe
             || (stop < Text_buffer.line_end source line && not (allowed_context_at source stop))
          then Or_error.error_string "Decoration replacement touches unsupported source context"
          else if original.width <> display.width
          then Or_error.error_string "Decoration replacement changes cell width"
          else
            let layout = Text_buffer.line_layout source ~width:Cell_map.width line in
            let pos = start - Text_buffer.line_start source line in
            let col, width = Cell_layout.Index.cursor_span layout ~pos ~insertion:false in
            if width <> original.width
            then Or_error.error_string "Decoration source geometry does not match cell layout"
            else Ok { range; col; width; source_text; text; role }
    in
    let open Or_error.Let_syntax in
    let%map replacements =
      Snapshot.operations snapshot
      |> List.filter_map ~f:(function
        | Snapshot.Operation.Style _ -> None
        | Replace { range; text; role } -> Some (prepare_replacement range text role))
      |> Or_error.all
    in
    { snapshot; source; replacements = Array.of_list replacements }
;;

let replacement_at t offset =
  match
    Array.binary_search t.replacements `First_equal_to offset
      ~compare:(fun replacement offset -> Int.compare replacement.range.start offset)
  with
  | None -> None
  | Some index -> Some t.replacements.(index)
;;

let apply t ~line_start glyphs =
  if Array.is_empty t.replacements then glyphs
  else
    Array.map glyphs ~f:(fun (glyph : Cell_map.Glyph.t) ->
      match replacement_at t (line_start + glyph.pos) with
      | Some replacement
        when glyph.col = replacement.col && glyph.width = replacement.width
             && Cell_map.Kind.equal glyph.kind Plain
             && String.equal glyph.text replacement.source_text ->
        { glyph with text = replacement.text }
      | Some _ | None -> glyph)
;;

let lookup_from t ~line_start =
  let style_at = Snapshot.lookup_from t.snapshot line_start in
  fun (glyph : Cell_map.Glyph.t) ->
    if Cell_map.Kind.equal glyph.kind Escape then None
    else
      let offset = line_start + glyph.pos in
      let role =
        match replacement_at t offset with
        | Some { role = Some role; _ } -> Some role
        | Some _ | None -> style_at offset
      in
      Option.map role ~f:syntax_of_role
;;
