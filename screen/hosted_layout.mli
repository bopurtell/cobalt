(** Initial layout for a hosted workspace. The document is always the primary
    surface; modals, pickers and directory navigation are opened by commands. *)

module View : sig
  type t = Problems | History | Language_servers | Vcs
  [@@deriving sexp, equal]
end

module Placement = Cobalt_input.View_command.Placement

module Status : sig
  module Position = Cobalt_input.View_command.Status_position

  type t =
    { position : Position.t
    ; size : int (** Requested cells along the split axis. *)
    }
  [@@deriving sexp, equal]
end

module Split = Workspace.Major_split

type t [@@deriving sexp, equal]

(** Unlisted views and omitted Status start hidden but remain available through
    their ordinary commands. Band and Tab entries are ordered as listed; Tab
    entries start inactive. Rejects duplicate views, multiple Split entries,
    and out-of-range sizes. The S-expression codec enforces the same constraints.

    For example, [((views ((Problems Band))))] selects only Problems below the
    document. A status pane can be added with [(status ((position Right)
    (size 28)))], and a split's requested share set with
    [(split ((view_side Left) (percent 40)))]. *)
val create
  :  ?status:Status.t
  -> ?split:Split.t
  -> views:(View.t * Placement.t) list
  -> unit
  -> t Core.Or_error.t

val placements : t -> (Cobalt_tile.View_id.t * Placement.t) list
val workspace_prefs : t -> Workspace.Prefs.t
val split : t -> Split.t
