open! Core

let layout (tabs : Tab_strip.Item.t list) ~width =
  let width = Int.max 0 width in
  if width = 0 then [] else
  let tabs = Array.of_list tabs in
  let count = Array.length tabs in
  if count = 0 then [ [ Span.blank Status width ], None ] else
  let active = Option.value (Array.findi tabs ~f:(fun _ t -> t.active) |> Option.map ~f:fst) ~default:0 in
  let token i ~limit =
    let t = tabs.(i) in
    let style = if t.active then Style.Title else Hint in
    let of_text text = Span.create style text ~width:(String.length text) in
    let prefix = sprintf "%s%d:" (if t.active then "[" else " ") (i + 1) in
    let suffix = (if t.missing then "!" else "") ^ (if t.modified then "*" else "") ^ (if t.active then "]" else " ") in
    let room = limit - String.length prefix - String.length suffix in
    if room < 1 then
      [ of_text (String.prefix (if t.missing then "!" else if t.modified then "*" else "[" ^ Int.to_string (i + 1)) limit) ], false
    else
      let label = Span.of_text t.label ~style ~special:style in
      let label = if Span.total_width label <= room then label
        else Span.take label ~n:(room - 1) @ [ of_text "~" ] in
      Span.merge ([ of_text prefix ] @ label @ [ of_text suffix ]), not t.active in
  let preferred = Array.init count ~f:(fun i -> lazy (token i ~limit:40)) in
  let lo = ref active and hi = ref active in
  let cost l h =
    (if l > 0 then 1 else 0) + (if h < count - 1 then 1 else 0)
    + List.sum (module Int) (List.range l (h + 1)) ~f:(fun i -> Span.total_width (fst (Lazy.force preferred.(i)))) in
  (* Prefer the preceding neighbor, then the following one; never skip a tab. *)
  let rec grow () =
    if !lo > 0 && cost (!lo - 1) !hi <= width then (decr lo; grow ())
    else if !hi < count - 1 && cost !lo (!hi + 1) <= width then (incr hi; grow ()) in
  grow ();
  let left = if !lo > 0 && width >= 3 then 1 else 0 in
  let right = if !hi < count - 1 && width >= 3 then 1 else 0 in
  let available = width - left - right in
  let body = List.map (List.range !lo (!hi + 1)) ~f:(fun i ->
    let spans, has_separator = if available >= 40 then Lazy.force preferred.(i) else token i ~limit:available in
    spans, Some (i, has_separator)) in
  let used = List.sum (module Int) body ~f:(fun (spans, _) -> Span.total_width spans) in
  (if left = 1 then [ [ Span.create Hint "<" ~width:1 ], None ] else [])
  @ body @ [ [ Span.blank Status (available - used) ], None ]
  @ (if right = 1 then [ [ Span.create Hint ">" ~width:1 ], None ] else [])
;;

let render_items tabs ~width = List.concat_map (layout tabs ~width) ~f:fst

let hit tabs ~width ~column =
  let rec seek column = function
    | [] -> None
    | (spans, tab) :: rest ->
      let width = Span.total_width spans in
      if column >= width then seek (column - width) rest
      else if column < 0 then None
      else Option.bind tab ~f:(fun (i, has_separator) ->
        Option.some_if (not has_separator || (column > 0 && column < width - 1)) i)
  in
  seek column (layout tabs ~width)
;;

let render tabs ~width = render_items (List.map tabs ~f:Tab_strip.Item.of_file) ~width
;;
