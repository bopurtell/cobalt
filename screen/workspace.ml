open! Core

module Pane_id = struct
  type t =
    | Document
    | Status
    | Minor of Cobalt_tile.View_id.t
  [@@deriving sexp_of, equal]
end

module Split = struct
  module Axis = struct
    type t =
      | Horizontal
      | Vertical
    [@@deriving sexp_of, equal]
  end

  type t =
    { axis : Axis.t
    ; first : Pane_id.t
    ; status_size : int
    }
  [@@deriving sexp_of, equal]

  let default = { axis = Horizontal; first = Document; status_size = 28 }
end

module Major_split = struct
  module Side = struct
    type t =
      | Left
      | Right
    [@@deriving sexp, equal]
  end

  type t =
    { view_side : Side.t
    ; percent : int
    }
  [@@deriving sexp, equal]

  let min_percent = 20
  let max_percent = 80
  let default = { view_side = Right; percent = 50 }

  let swap t =
    { t with
      view_side =
        (match t.view_side with
         | Left -> Right
         | Right -> Left)
    }
  ;;

  let adjust t points =
    { t with percent = Int.clamp_exn (t.percent + points) ~min:min_percent ~max:max_percent }
  ;;
end

module Prefs = struct
  type t =
    { status_visible : bool
    ; split : Split.t
    }
  [@@deriving sexp_of, equal]

  let default = { status_visible = false; split = Split.default }
end

module Pane = struct
  type t =
    { id : Pane_id.t
    ; rect : Geometry.Rect.t
    }
  [@@deriving sexp_of, equal]
end

type t =
  { document : Pane.t
  ; second_editor : Geometry.Rect.t option
  ; status : Pane.t option
  ; minors : Pane.t list
  ; gaps : Geometry.Rect.t list
  ; reserve_status_row : bool
  }
[@@deriving sexp_of, equal]

let min_document_width = 16
let min_document_height = 1
let min_status_width = 8
let min_status_height = 3
let min_minor_width = 16
let min_split_width = 24
let gap = 1
let min_band_height = 3
let preferred_band_height = 10

let allocate_pair (prefs : Prefs.t) ~(allocation : Geometry.Rect.t) =
  let allocation =
    { allocation with
      width = Int.max 0 allocation.width
    ; height = Int.max 0 allocation.height
    }
  in
  let fits =
    match prefs.split.axis with
    | Horizontal ->
      allocation.width >= min_document_width + gap + min_status_width
      && allocation.height >= Int.max min_document_height min_status_height
    | Vertical ->
      allocation.width >= Int.max min_document_width min_status_width
      && allocation.height >= min_document_height + min_status_height
  in
  if not prefs.status_visible || not fits
  then
    { document = { id = Document; rect = allocation }
    ; second_editor = None
    ; status = None
    ; minors = []
    ; gaps = []
    ; reserve_status_row = true
    }
  else (
    let horizontal = Split.Axis.equal prefs.split.axis Horizontal in
    (* Side-by-side tiles are separated by a backdrop gap; stacked frames already are
       by their own border rows. *)
    let available, status_min, document_min, gap =
      if horizontal
      then allocation.width - gap, min_status_width, min_document_width, gap
      else allocation.height, min_status_height, min_document_height, 0
    in
    let status_size =
      Int.clamp_exn prefs.split.status_size ~min:status_min ~max:(available - document_min)
    in
    let document_size = available - status_size in
    let status_first = Pane_id.equal prefs.split.first Status in
    let document_start = if status_first then status_size + gap else 0 in
    let status_start = if status_first then 0 else document_size + gap in
    let rect start size =
      if horizontal
      then { allocation with x = allocation.x + start; width = size }
      else { allocation with y = allocation.y + start; height = size }
    in
    { document = { id = Document; rect = rect document_start document_size }
    ; second_editor = None
    ; status = Some { id = Status; rect = rect status_start status_size }
    ; minors = []
    ; gaps =
        (if gap = 0
         then []
         else [ rect (if status_first then status_size else document_size) gap ])
    ; reserve_status_row = false
    })
;;

let allocate_band ?(minors = []) ?(major = true) prefs ~(allocation : Geometry.Rect.t) =
  let allocation =
    { allocation with width = Int.max 0 allocation.width; height = Int.max 0 allocation.height }
  in
  let upper ~allocation =
    if major then allocate_pair prefs ~allocation else
      let status = Option.some_if
          (prefs.Prefs.status_visible && allocation.width >= min_status_width
           && allocation.height >= min_status_height)
          { Pane.id = Status; rect = allocation } in
      { document = { id = Document; rect = { allocation with width = 0; height = 0 } }
      ; second_editor = None; status; minors = []; gaps = []; reserve_status_row = false }
  in
  let original = upper ~allocation in
  (* Document/status minima take precedence over the band. *)
  let minimum =
    match original.status, prefs.split.axis with
    | Some _, Split.Axis.Vertical when major -> min_document_height + min_status_height
    | Some _, _ -> min_status_height
    | None, _ -> if major then 2 else 0
  in
  let minors = List.take minors ((allocation.width + gap) / (min_minor_width + gap)) in
  if List.is_empty minors || allocation.width < min_document_width
     || allocation.height < minimum + min_band_height
  then original
  else (
    (* The band keeps the upper workspace at least two thirds of the height. *)
    let size =
      if minimum = 0 then allocation.height else Int.min
        (Int.min preferred_band_height (allocation.height - minimum))
        (Int.max min_band_height (allocation.height / 3))
    in
    let upper_rect = { allocation with height = allocation.height - size } in
    let workspace = upper ~allocation:upper_rect in
    let count = List.length minors in
    let shared = allocation.width - ((count - 1) * gap) in
    let start i = (shared * i / count) + (i * gap) in
    let minors =
      List.mapi minors ~f:(fun i id ->
        { Pane.id = Minor id
        ; rect =
            { Geometry.Rect.x = allocation.x + start i
             ; y = allocation.y + upper_rect.height
            ; width = (shared * (i + 1) / count) - (shared * i / count)
            ; height = size
            }
        })
    in
    let gaps =
      List.init (count - 1) ~f:(fun i ->
        { Geometry.Rect.x = allocation.x + start (i + 1) - gap
         ; y = allocation.y + upper_rect.height
        ; width = gap
        ; height = size
        })
    in
    { workspace with minors; gaps = workspace.gaps @ gaps })
;;

let divide (area : Geometry.Rect.t) (request : Major_split.t) ~min_width ~min_height =
  let available = area.width - gap in
  if available < min_document_width + min_width || area.height < min_height
  then None
  else (
    let size =
      Int.clamp_exn (available * request.percent / 100) ~min:min_width
        ~max:(available - min_document_width)
    in
    let document_width = available - size in
    let view_x, document_x, gap_x =
      match request.view_side with
      | Right -> area.x + document_width + gap, area.x, area.x + document_width
      | Left -> area.x, area.x + size + gap, area.x + size
    in
    Some ({ area with x = document_x; width = document_width },
      { area with x = view_x; width = size }, { area with x = gap_x; width = gap }))
;;

(* Divide the document's allocation between the active tab and the split view. *)
let allocate_split t (id, request) =
  match divide t.document.rect request ~min_width:min_split_width ~min_height:min_band_height with
  | None -> t
  | Some (document, view, gap) ->
    { t with document = { t.document with rect = document }
    ; minors = t.minors @ [ { Pane.id = Minor id; rect = view } ]
    ; gaps = t.gaps @ [ gap ] }
;;

let allocate_editors t ~secondary_focused request =
  (* Shared tabs, a pane title, a text row, and potentially a feedback row. *)
  match divide t.document.rect request ~min_width:min_document_width ~min_height:4 with
  | None -> t
  | Some (primary, secondary, gap) ->
    let focused, other = if secondary_focused then secondary, primary else primary, secondary in
    { t with document = { t.document with rect = focused }
    ; second_editor = Some other; gaps = t.gaps @ [ gap ] }
;;

let allocate_side ~minors ~major ?side prefs ~(allocation : Geometry.Rect.t) =
  match side with
  | Some (id, _) when not major && not prefs.Prefs.status_visible && List.is_empty minors
                      && allocation.width >= min_minor_width && allocation.height >= 4 ->
    let workspace = allocate_band ~major prefs ~allocation in
    { workspace with minors = [ { Pane.id = Minor id; rect = allocation } ] }
  | Some (id, preferred) when allocation.width >= 16 + gap + min_document_width && allocation.height >= 4 ->
    let size = Int.clamp_exn preferred ~min:16 ~max:(allocation.width - gap - min_document_width) in
    let rect = { allocation with width = size } in
    let rest = { allocation with x = allocation.x + size + gap; width = allocation.width - size - gap } in
    let workspace = allocate_band ~minors ~major prefs ~allocation:rest in
    { workspace with minors = { Pane.id = Minor id; rect } :: workspace.minors
      ; gaps = { allocation with x = allocation.x + size; width = gap } :: workspace.gaps }
  | _ -> allocate_band ~minors ~major prefs ~allocation
;;

let allocate ?(minors = []) ?side ?split ?editors ?(document_visible = true)
    prefs ~(allocation : Geometry.Rect.t) =
  let allocation = { allocation with width = Int.max 0 allocation.width; height = Int.max 0 allocation.height } in
  let major = document_visible || Option.is_some split || Option.is_some editors in
  let base = allocate_side ~minors ~major ?side prefs ~allocation in
  if document_visible then (
    match split, editors with
    | Some split, _ -> allocate_split base split
    | None, Some (secondary_focused, request) -> allocate_editors base ~secondary_focused request
    | None, None -> base)
  else (
    let rect = base.document.rect in
    let base = { base with document = { base.document with rect = { rect with width = 0; height = 0 } }
      ; reserve_status_row = false } in
    match split, editors with
    | Some (id, _), _ when rect.width >= min_split_width && rect.height >= min_band_height ->
      { base with minors = base.minors @ [ { Pane.id = Minor id; rect } ] }
    | None, Some _ when rect.width >= min_document_width && rect.height >= 4 ->
      { base with second_editor = Some rect }
    | _ -> base)
;;

let minor t id =
  List.find t.minors ~f:(fun pane -> Pane_id.equal pane.id (Minor id))
;;

let document_geometry t prefs ~line_count =
  Geometry.compute_in prefs
    ~allocation:t.document.rect
    ~reserve_status_row:t.reserve_status_row
    ~line_count
;;
