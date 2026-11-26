(** Read-only Silver connection choices. Lookup does not contact or start any
    daemon; [connect] performs the live handshake for the chosen candidate. *)

type source =
  | Advertised
  | Known
  | Explicit

type candidate

val endpoint : candidate -> string
val source : candidate -> source

type lookup =
  { candidates : candidate list
  ; advertisement_error : string option
  }

(** Read at most one Silver [daemon.sexp] advertisement. The default directory
    matches Silver's native client: [$XDG_RUNTIME_DIR/silver], or
    [$XDG_STATE_HOME/silver], or
    [$HOME/.local/state/silver]. [directory] can name the exact
    directory passed to Silver's [--discovery-dir]. A missing file is normal.
    Within the selected parent, an existing [hardcaml-workbench] directory
    is used when [silver] is absent; coexistence reports a conflict.

    [known] is caller-supplied (for example, the current configured endpoint).
    Invalid known entries are omitted. Duplicates favor the advertisement so
    the daemon instance check is not lost. No other directories or ports are
    searched. *)
val lookup : ?directory:string -> ?known:string list -> unit -> lookup Async.Deferred.t

(** Validate an explicitly entered loopback HTTP endpoint without doing I/O. *)
val explicit : string -> (candidate, string) result

(** Verify Silver v1 and its simulation capability, and require an advertised
    instance ID to match. Only then open the exact canonical [project_root].
    Does not launch a run or change the watched attempt. *)
val connect
  :  ?peer:Silver_overview.peer
  -> ?timeout:Core.Time_ns.Span.t
  -> candidate
  -> project_root:string
  -> (Silver_overview.Testing.project, string) result Async.Deferred.t

(** WB-094 project shares, separate from native daemon discovery. *)
module Share : sig
  type mode = Embedded | Attached
  type t
  type lookup = { shares : t list; error : string option }

  val offer_id : t -> string
  val endpoint : t -> string
  val instance_id : t -> string
  val project_id : t -> string
  val project_root : t -> string
  val mode : t -> mode option

  (** Read one bounded, owner-controlled fixture file, without contacting peers.
      Fixture rows have no [mode]. *)
  val lookup : file:string -> lookup Async.Deferred.t

  (** List locked v1 offers only in [editor-shares/v1] under Silver's native
      runtime directory, without contacting peers or making any files. *)
  val lookup_live : ?directory:string -> unit -> lookup Async.Deferred.t

  (** Re-read the exact offer before and after verifying its live project.
      Neither opens a replacement project nor submits work. *)
  val connect
    :  ?peer:Silver_overview.peer
    -> ?timeout:Core.Time_ns.Span.t
    -> t
    -> (Silver_overview.Testing.project, string) result Async.Deferred.t
end
