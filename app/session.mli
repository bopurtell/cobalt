open! Core
open Cobalt_core
open Cobalt_input
type t
type placement = Major | Side
type directory_presentation =
  { buffer : Buffer_id.t; placement : placement; target_group : Group_id.t; return_target : Buffer_id.t option }
val directory_presentation : t -> directory_presentation option
(** [project_root] binds location requests to this session for its lifetime. It
    defaults to the initial {!startup_directory}; a relative override is resolved
    against [cwd]. *)
val create : ?cwd:string -> ?project_root:string -> ?keymap_config:Keymap.Config.t -> ?directory_config:Directory_buffer.Config.t -> cell_width:Cell_layout.Width.t -> Controller.t -> t
val buffers : t -> (Buffer_id.t * Controller.t) list
val buffer_count : t -> int
(** Path/membership-only cached labels in tab order; flags come from current controllers. *)
val buffer_labels : t -> (Buffer_id.t * string) list
(** Drain coalesced file lifetime/revision changes in tab order. Closed IDs have
    no controller. Directory surfaces and feedback/register changes are excluded. *)
val take_source_changes : t -> t * (Buffer_id.t * (int * Controller.t) option) list
(** Constant-time conservative invalidation predicates for retained UI state. *)
val same_file_lifetimes : t -> t -> bool
val same_buffer_membership : t -> t -> bool
(** Active file tab underneath any major directory presentation. *)
val active_id : t -> Buffer_id.t option
type editor_split = { other : Buffer_id.t; active_secondary : bool }
(** The other buffer and whether the active file occupies the secondary slot.
    The requested split is independent of screen visibility. *)
val editor_split : t -> editor_split option
(** Split the active file with a distinct retained tab, or open a second file
    transactionally. The secondary slot becomes active. *)
val split_with : t -> Buffer_id.t -> t Or_error.t
val split_open_file : t -> string -> (t * Buffer_id.t) Or_error.t
(** Keep the active file visible; neither tab is closed. *)
val close_editor_split : t -> t
(** Read-only drawing snapshot; do not adopt or dispatch it. *)
val editor_surface : t -> Buffer_id.t -> t
(** Visible input owner, not necessarily the active file tab. *)
val context_id : t -> Buffer_id.t option
val has_buffer : t -> Buffer_id.t -> bool
(** Presented browser, including an unfocused side browser. *)
val directory_buffer : t -> Directory_buffer.t option
(** Directory adapter only when it owns modal input. *)
val input_directory : t -> Directory_buffer.t option
(** Cancel prefixes on both owners; preserve directory selection and text state. *)
val focus_directory : t -> bool -> t
val set_directory_placement : t -> placement -> t
val hide_directory : t -> t
(** Read-only snapshot for drawing either retained surface; do not adopt it. *)
val surface : t -> directory:bool -> t
val show_directory : ?select:string -> t -> string -> t Or_error.t
val group_id : t -> Group_id.t
val startup_directory : t -> string
val project_root : t -> string
val normalize : t -> string -> string
val find : t -> Buffer_id.t -> Controller.t option
val source_generation : t -> Buffer_id.t -> int option
val find_resource : t -> string -> (Buffer_id.t * Controller.t) option
type resource_buffer = File_buffer of Buffer_id.t * Controller.t | Directory_buffer of Directory_buffer.t
val find_resource_buffer : t -> string -> resource_buffer option
val active_controller : t -> Controller.t option
(** Collect document-local effects and synchronize session feedback/register.
     The replacement must belong to the same active buffer; resource reassociation
     is session-owned, not arbitrary controller replacement. *)
val replace_active : t -> Controller.t -> t
(** [must_exist] rejects missing new resources. Already retained buffers are
     activated without rereading disk, including dirty or missing buffers.
     Validation runs before activation/registration. Returned errors or exceptions
     preserve session state and close a newly loaded controller. *)
val open_or_activate : ?must_exist:bool -> ?validate:(Controller.t -> unit Or_error.t)
  -> t -> string -> (t * Buffer_id.t) Or_error.t

module Open_location : sig
  (** One-based line and one-based terminal display column, using the session's
      width function. For [é界x], with widths 1/2/1, columns 2 and 3 select [界]
      and column 4 selects [x], which is at UTF-8 byte offset 5 on the line. *)
  type position = { line : int; column : int }

  type request =
    { project_root : string
    ; relative_file : string
    ; position : position option
    }

  type failure =
    | Session_exited
    | Wrong_project of { expected : string; requested : string }
    | Invalid_relative_file of string
    | Target_unavailable of Error.t
    | Invalid_position of Error.t
  [@@deriving sexp_of]

  val to_error : failure -> Error.t
end

(** Open an existing file or activate its retained buffer, without reloading
    retained text from disk. The request root must be absolute and match the
    bound root after lexical normalization. The path must be relative and
    resolve strictly below that root; ordinary file opens follow symlinks, so
    this check is not a filesystem sandbox.

    [None] leaves the target cursor alone. [Some position] uses normal document
    navigation, finishing Insert/Visual if necessary. Validation uses the
    retained text when present. On failure there is no new buffer, activation,
    or cursor/mode change. On success the caller adopts the returned session and
    uses the returned ID to present the active buffer. *)
val open_location : t -> Open_location.request -> (t * Buffer_id.t, Open_location.failure) Result.t

val activate : t -> Buffer_id.t -> t Or_error.t
val close_buffer : t -> Buffer_id.t -> force:bool -> t * bool
val close_current : t -> force:bool -> t * bool
(** Directory save explicitly applies validated create/rename/copy/permanent-delete proposals; never
    writes listing text. Partial failures retain reconciled unresolved intent. *)
val save_current : t -> t
val recreate_current : t -> t
(** Exclusive save-as; refuses existing destinations, reindexes the same buffer. *)
val save_as : t -> Buffer_id.t -> string -> t Or_error.t
(** Dirty file and retained directory buffers in ID order; continue on error. *)
val save_all : t -> t * (Buffer_id.t * bool) list
(** Write retained file buffer [id] now, as [:w] would with it active, even when it
    is clean; the active buffer is unchanged. A success is recorded like any save
    ({!saved}). An error says why nothing was written: not an open file buffer (a
    directory buffer, an unknown id), a buffer marked missing, or the write's own
    failure (["Failed to write <path>: <reason>"], also kept as the buffer's save
    problem, as [:w] keeps it). *)
val save_buffer : t -> Buffer_id.t -> t * unit Or_error.t
val quit : t -> force:bool -> t * Controller.Status.t
(** What {!reconcile} did, per retained file buffer (tab order); unchanged buffers
    are not listed. *)
module Reconciled : sig
  type t =
    { reloaded : Buffer_id.t list (** Clean, changed on disk (or back from missing). *)
    ; missing : Buffer_id.t list (** Clean, file gone: marked missing. *)
    ; dirty : Buffer_id.t list (** Unsaved changes: untouched, not read. *)
    ; busy : Buffer_id.t list (** Buffers in Insert/Visual: untouched. *)
    ; failed : (Buffer_id.t * Error.t) list (** Unreadable: untouched. *)
    }
  [@@deriving sexp_of]
end

(** Open-buffer reconciliation after something outside Cobalt may have rewritten files
    (a VCS discard, checkout or pull): every retained file buffer whose path is within
    one of [under] (absolute, lexical: {!Resource.within}) is passed through
    {!Controller.reconcile_with_disk}, the active one included. Synchronous: reads
    each such file once in the transition, as save and open already do; nothing is
    watched. Reloads keep the buffer's id (so the UI keeps its scroll), cursor line
    and column, and count as source changes ({!take_source_changes}). Feedback: a
    reload failure is a [Failed] reload problem (a success resolves it, as [:e!]
    does), and one [session] notification lists the reloaded, missing, dirty and
    busy buffers by label (Info, or Warning when any were not reloaded); nothing is
    posted when nothing changed, and the session is then returned unchanged. *)
val reconcile : t -> under:string list -> t * Reconciled.t
val dispatch : t -> Keymap.Action.t list -> t * View_command.t list * Controller.Status.t
val handle_input : t -> Keymap.Input.t -> t * View_command.t list * Controller.Status.t
val feedback : t -> Cobalt_error.Error.t
val take_clipboard : t -> t * string option
val take_saved : t -> t * Controller.Saved.t list

(** What {!take_saved} would return now (oldest first), without taking it. Saves of
    the active controller count once it is passed to {!replace_active}. *)
val saved : t -> Controller.Saved.t list
val take_directory_changes : t -> t * string list

(** What {!take_directory_changes} would return now: the absolute paths directory-buffer
    saves (save, {!save_all}, quit, either placement) changed on disk, oldest first,
    each once per save: created and copied-to paths, deleted paths, and both sides of
    a rename (a directory operation names the directory, not its contents). A partly
    failed apply lists only the operations that happened, a staging name it left
    behind included. Kept out of {!saved} (no document was written) and never
    relocated by later renames. *)
val directory_changes : t -> string list
val take_closed : t -> t * string list
val exited : t -> bool
val dispose : t -> unit
module For_testing : sig
  (** Fault injection for isolated filesystem fixtures only. *)
  val save_directory : t -> Buffer_id.t -> before_mutation:(int -> unit) -> t
end
