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
    matches Silver's native client: [$XDG_RUNTIME_DIR/hardcaml-workbench], or
    [$XDG_STATE_HOME/hardcaml-workbench], or
    [$HOME/.local/state/hardcaml-workbench]. [directory] can name the exact
    directory passed to Silver's [--discovery-dir]. A missing file is normal.

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
