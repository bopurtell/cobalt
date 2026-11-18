open! Core

module Role = struct
  type t = Accent | Literal | Muted [@@deriving sexp_of, equal, compare]
end

module Document_id = struct
  type t = unit ref
  let create () = ref ()
end

module Key = struct
  type t =
    { document : Document_id.t
    ; revision : int
    ; provider : string
    ; configuration : string
    }

  let create ~document ~revision ~provider ~configuration =
    { document; revision; provider; configuration }
  ;;
  let same_document a b = phys_equal a.document b.document
  let equal a b =
    same_document a b
    && Int.equal a.revision b.revision
    && String.equal a.provider b.provider
    && String.equal a.configuration b.configuration
  ;;
  let revision t = t.revision
  let provider t = t.provider
  let configuration t = t.configuration
end

module Range = struct
  type t = { start : int; stop : int } [@@deriving sexp_of, equal, compare]
end

module Operation = struct
  type t =
    | Style of { range : Range.t; role : Role.t }
    | Replace of { range : Range.t; text : string; role : Role.t option }
  [@@deriving sexp_of, equal]

  let range = function
    | Style { range; _ } | Replace { range; _ } -> range
  ;;

  let compare a b =
    let c = Range.compare (range a) (range b) in
    if c <> 0 then c else
    match a, b with
    | Style a, Style b -> Role.compare a.role b.role
    | Style _, Replace _ -> -1
    | Replace _, Style _ -> 1
    | Replace a, Replace b ->
      let c = Option.compare Role.compare a.role b.role in
      if c <> 0 then c else String.compare a.text b.text
  ;;
end

module Limits = struct
  type t =
    { max_source_bytes : int
    ; max_operations : int
    ; max_replacement_bytes : int
    ; max_total_replacement_bytes : int
    }
  [@@deriving sexp_of]

  let default =
    { max_source_bytes = 16 * 1024 * 1024
    ; max_operations = 4096
    ; max_replacement_bytes = 4096
    ; max_total_replacement_bytes = 65536
    }
  ;;
end

module Ranked_style = struct
  module T = struct
    type t = { range : Range.t; role : Role.t } [@@deriving sexp_of]
    let compare a b =
      let c =
        Int.compare (a.range.stop - a.range.start) (b.range.stop - b.range.start)
      in
      if c <> 0 then c else
      let c = Role.compare a.role b.role in
      if c <> 0 then c else Range.compare a.range b.range
    ;;
  end
  include T
  include Comparator.Make (T)
end

type style_span = { start : int; stop : int; role : Role.t }

(* The interval tree retains raw operations (including crossing Styles), while
   the disjoint sweep index provides direct Style lookup without rescanning them. *)
type operation_index =
  | Empty
  | Node of
      { operation : Operation.t
      ; left : operation_index
      ; right : operation_index
      ; min_start : int
      ; max_stop : int
      }

type t =
  { key : Key.t
  ; source_length : int
  ; operations : Operation.t list
  ; index : operation_index
  ; styles : style_span array
  }

let key t = t.key
let matches t key = Key.equal t.key key
let operations t = t.operations
let is_empty t = List.is_empty t.operations
let source_length t = t.source_length

let error message = Error (Error.of_string ("Snapshot.create: " ^ message))

let check_budgets (limits : Limits.t) ~source operations =
  if limits.max_source_bytes < 0
     || limits.max_operations < 0
     || limits.max_replacement_bytes < 0
     || limits.max_total_replacement_bytes < 0
  then error "limits must be nonnegative"
  else if String.length source > limits.max_source_bytes
  then error "source byte limit exceeded"
  else
    (* Do not compute List.length, copy operations, scan text, or sum lengths
       before enforcing budgets. Subtraction avoids integer overflow. *)
    let rec loop operations count total =
      match operations with
      | [] -> Ok ()
      | _ :: _ when count >= limits.max_operations ->
        error "operation count limit exceeded"
      | operation :: rest ->
        (match operation with
         | Operation.Style _ -> loop rest (count + 1) total
         | Replace { text; _ } ->
           let length = String.length text in
           if length > limits.max_replacement_bytes
           then error "replacement byte limit exceeded"
           else if length > limits.max_total_replacement_bytes - total
           then error "total replacement byte limit exceeded"
           else loop rest (count + 1) (total + length))
    in
    loop operations 0 0
;;

let check_ranges ~source operations =
  let length = String.length source in
  let boundary at =
    at >= 0 && at <= length
    && (at = length || Char.to_int source.[at] land 0xc0 <> 0x80)
  in
  if List.for_all operations ~f:(fun operation ->
    let range = Operation.range operation in
    range.start < range.stop && boundary range.start && boundary range.stop)
  then Ok ()
  else error "range must be nonempty, in bounds, and at UTF-8 scalar boundaries"
;;

let check_replacement_overlap operations =
  let rec loop operations previous_stop =
    match operations with
    | [] -> Ok ()
    | Operation.Style _ :: rest -> loop rest previous_stop
    | Replace { range; _ } :: rest ->
      if range.start < previous_stop
      then error "overlapping replacements"
      else loop rest range.stop
  in
  loop operations 0
;;

let replacement_has_control text =
  let length = String.length text in
  let rec loop i =
    if i = length then false else
    let byte = Char.to_int text.[i] in
    byte < 0x20 || byte = 0x7f
    || (byte = 0xc2 && i + 1 < length
        && Char.to_int text.[i + 1] >= 0x80
        && Char.to_int text.[i + 1] <= 0x9f)
    || loop (i + 1)
  in
  loop 0
;;

let check_replacement_text ~source operations =
  let rec contains_lf at stop =
    at < stop && (Char.equal source.[at] '\n' || contains_lf (at + 1) stop)
  in
  let rec loop = function
    | [] -> Ok ()
    | Operation.Style _ :: rest -> loop rest
    | Replace { range; text; _ } :: rest ->
      if not (Stdlib.String.is_valid_utf_8 text)
      then error "invalid UTF-8 replacement"
      else if replacement_has_control text
      then error "replacement contains a C0/C1 control"
      else if contains_lf range.start range.stop
      then error "replacement source range contains LF"
      else loop rest
  in
  loop operations
;;

let build_index operations =
  let operations = Array.of_list operations in
  let rec build lo hi =
    if lo = hi then Empty else
    let mid = lo + (hi - lo) / 2 in
    let operation = operations.(mid) in
    let range = Operation.range operation in
    let left = build lo mid in
    let right = build (mid + 1) hi in
    let min_start =
      match left with Empty -> range.start | Node node -> node.min_start
    in
    let max_stop =
      List.fold [ left; right ] ~init:range.stop ~f:(fun stop -> function
        | Empty -> stop
        | Node node -> Int.max stop node.max_stop)
    in
    Node { operation; left; right; min_start; max_stop }
  in
  build 0 (Array.length operations)
;;

let build_styles operations =
  let events =
    List.concat_map operations ~f:(function
      | Operation.Replace _ -> []
      | Style { range; role } ->
        let style = { Ranked_style.range; role } in
        [ range.start, true, style; range.stop, false, style ])
    |> List.sort ~compare:(fun (a, _, _) (b, _, _) -> Int.compare a b)
  in
  let emit acc start stop role =
    match acc with
    | previous :: rest
      when previous.stop = start && Role.equal previous.role role ->
      { previous with stop } :: rest
    | _ -> { start; stop; role } :: acc
  in
  let rec sweep events active previous acc =
    match events with
    | [] -> Array.of_list (List.rev acc)
    | (at, _, _) :: _ ->
      let acc =
        match Set.min_elt active with
        | Some (style : Ranked_style.t) when previous < at ->
          emit acc previous at style.role
        | _ -> acc
      in
      let here, rest = List.split_while events ~f:(fun (offset, _, _) -> offset = at) in
      let active = List.fold here ~init:active ~f:(fun set (_, add, style) ->
        if add then Set.add set style else Set.remove set style)
      in
      sweep rest active at acc
  in
  sweep events (Set.empty (module Ranked_style)) 0 []
;;

let create ?(limits = Limits.default) ~key ~source operations =
  let open Result.Let_syntax in
  let%bind () = check_budgets limits ~source operations in
  let%bind () =
    if Stdlib.String.is_valid_utf_8 source
    then Ok () else error "invalid UTF-8 source"
  in
  let%bind () = check_ranges ~source operations in
  let operations = List.sort operations ~compare:Operation.compare in
  let%bind () = check_replacement_overlap operations in
  let%bind () = check_replacement_text ~source operations in
  Ok
    { key
    ; source_length = String.length source
    ; operations
    ; index = build_index operations
    ; styles = build_styles operations
    }
;;

let intersecting t ~start ~stop =
  let rec visit index acc =
    match index with
    | Empty -> acc
    | Node node ->
      if node.max_stop <= start || node.min_start >= stop then acc else
      let acc = visit node.right acc in
      let range = Operation.range node.operation in
      let acc =
        if range.start < stop && start < range.stop
        then node.operation :: acc else acc
      in
      visit node.left acc
  in
  if start >= stop then [] else visit t.index []
;;

let lower_bound t offset =
  let rec loop lo hi =
    if lo = hi then lo else
    let mid = lo + (hi - lo) / 2 in
    if t.styles.(mid).stop <= offset then loop (mid + 1) hi else loop lo mid
  in
  loop 0 (Array.length t.styles)
;;

let at_index t index offset =
  if index < Array.length t.styles && t.styles.(index).start <= offset
  then Some t.styles.(index).role else None
;;

let style_at t offset = at_index t (lower_bound t offset) offset
let role_at = style_at

let lookup_from t first =
  let index = ref (lower_bound t first) in
  let previous = ref first in
  fun offset ->
    if offset < !previous then index := lower_bound t offset;
    previous := offset;
    while !index < Array.length t.styles && t.styles.(!index).stop <= offset do
      incr index
    done;
    at_index t !index offset
;;
