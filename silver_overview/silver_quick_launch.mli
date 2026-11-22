(** Pure, session-local settings for Silver simulation quick launch. Keep [t] outside
    the tile and palette; opening or closing either does not update the model. *)

type project =
  { endpoint : string
  ; project_root : string
  }
(** Use the verified connection endpoint and canonical root, not the daemon's
    transient project ID or the editor's current buffer. *)

type case =
  { id : string
  ; label : string
  }

type parameter =
  { key : string
  ; label : string
  ; default : string
  ; choices : string list
  }

type suite =
  { id : string
  ; label : string
  ; cases : case list
  ; parameters : parameter list
  ; default_seed : string
  }

type catalog =
  { discovery_digest : string
  ; suites : suite list
  }
(** Version-1 successful Silver discovery. [discovery_digest] comes from the
    daemon, not a hash of the client representation. *)

type target =
  | Suite of string
  | Variant of { suite_id : string; case_id : string }

type t
type catalog_view
type selected
type edit

val empty : t
val set_catalog : t -> project:project -> catalog -> t

(** Fence old selections and drafts, even if the next catalog has the same digest.
    Useful on reconnect or a server rejection reporting stale discovery. *)
val invalidate_catalog : t -> project:project -> reason:string -> t

(** May retain browse rows even when launching is blocked. Keep this view with
    the rendered rows so selecting an old row cannot pick from a new discovery. *)
val catalog_view : t -> project:project -> catalog_view option
val catalog_contents : catalog_view -> catalog
val catalog_error : t -> project:project -> string option

val select : t -> catalog_view -> target -> (t * selected, string) result
val selected_target : selected -> target

type field_id =
  | Seed
  | Parameter of string

type field =
  { id : field_id
  ; label : string
  ; value : string
  ; default : string
  ; choices : string list
  }

val begin_edit : t -> selected -> (edit, string) result
val fields : edit -> field list
val set_field : edit -> field_id -> string -> edit
val reset : edit -> edit

(** Save only non-default values for this exact row. Suite and variant settings
    are independent. Apply does not launch; a failed apply changes nothing. *)
val apply : t -> edit -> (t, string) result
val cancel : t -> edit -> t

type selection =
  { suite : string
  ; cases : string list
  ; seed : string
  ; parameters : (string * string) list
  }

(** The Silver [Simulation.Selection.t] wire representation, with [asic_inputs ()]
    for this launch path. A suite targets all its cases in discovery order; a
    variant targets its one case. All declared parameters are included. *)
val sexp_of_selection : selection -> Core.Sexp.t

type launch = private
  { project : project
  ; target : target
  ; discovery_digest : string
  ; catalog_generation : int
  ; selection : selection
  ; target_label : string
  ; non_defaults : (field_id * string) list
  ; display : string
  }

val resolve : t -> selected -> (launch, string) result

(** Call before submitting a captured launch if there may have been catalog
    updates since it was resolved (for example, while the palette was open). *)
val check_launch : t -> launch -> (unit, string) result

val set_configured_default : t -> project:project -> target option -> t

type alias =
  | Ready of launch
  | Pick_target
  | Blocked of string

(** Configured default takes priority over the last acknowledged target. Neither
    browsing nor applying changes the last launched target. A changed catalog
    requires explicitly reselecting the target before using the alias again. *)
val resolve_alias : t -> project:project -> alias

(** Record an acknowledged launch, not a rejection or a lost acknowledgement.
    If several launches overlap, call in order of launch (not reply arrival). *)
val record_launch : t -> launch -> t
