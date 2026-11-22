open! Core

module View = struct
  type t = Problems | History | Language_servers | Vcs
  [@@deriving sexp, equal]

  let id = function
    | Problems -> Problems_tile.id
    | History -> History_tile.id
    | Language_servers -> Language_servers_tile.id
    | Vcs -> Vcs_view.id
  ;;
end

module Placement = Cobalt_input.View_command.Placement

module Status = struct
  module Position = Cobalt_input.View_command.Status_position

  type t = { position : Position.t; size : int }
  [@@deriving sexp, equal]
end

module Split = Workspace.Major_split

type t =
  { views : (View.t * Placement.t) list [@default []] [@sexp_drop_default.equal]
  ; status : Status.t option [@sexp.option]
  ; split : Split.t [@default Split.default] [@sexp_drop_default.equal]
  }
[@@deriving sexp, equal]

let validate t =
  let ids = List.map t.views ~f:(fun (view, _) -> View.id view) in
  match List.find_a_dup ids ~compare:Cobalt_tile.View_id.compare with
  | Some id ->
    Or_error.errorf "Duplicate Cobalt layout view: %s" (Cobalt_tile.View_id.to_string id)
  | None ->
    if List.count t.views ~f:(fun (_, p) -> Placement.equal p Split) > 1
    then Or_error.error_string "Cobalt layout allows at most one Split view"
    else if Option.exists t.status ~f:(fun status -> status.size <= 0 || status.size > 500)
    then Or_error.error_string "Cobalt layout Status size must be between 1 and 500"
    else if t.split.percent < Split.min_percent || t.split.percent > Split.max_percent
    then Or_error.errorf "Cobalt layout Split percent must be between %d and %d"
      Split.min_percent Split.max_percent
    else Ok t
;;

let create ?status ?(split = Split.default) ~views () = validate { views; status; split }

let t_of_sexp sexp =
  match validate (t_of_sexp sexp) with
  | Ok t -> t
  | Error error -> Sexplib.Conv.of_sexp_error (Error.to_string_hum error) sexp
;;

let placements t = List.map t.views ~f:(fun (view, placement) -> View.id view, placement)
let split t = t.split

let workspace_prefs t : Workspace.Prefs.t =
  match t.status with
  | None -> Workspace.Prefs.default
  | Some { position; size } ->
    let axis, first =
      match position with
      | Left -> Workspace.Split.Axis.Horizontal, Workspace.Pane_id.Status
      | Right -> Horizontal, Document
      | Above -> Vertical, Status
      | Below -> Vertical, Document
    in
    { status_visible = true; split = { axis; first; status_size = size } }
;;
