# Forward an open to the main Cobalt editor (C4)

The standalone launcher may opt one session into receiving
[C1 open-location requests](../app/OPEN_LOCATION.md) for its bound project. This
is not a daemon, a command/palette API, or a buffer transfer. An open reuses the
destination's own unsaved buffer when it has one. Other running editors and
their unsaved contents are unaffected.

```sh
cobalt --main-editor /work/demo
cobalt-open --project /work/demo src/example.ml 8 4
# From this checkout:
dune exec -j 4 main_editor_sender/cobalt_open.exe -- --project /work/demo src/example.ml 8 4
```

The sending root is the receiver's startup directory (the directory passed
to Cobalt, or the parent of the file passed to it). Always name that absolute
root explicitly. The optional position is
one-based (line and terminal display column, not bytes). With no position, the
destination leaves the file's cursor alone; with only a line, the sender uses
column 1. The sender exits `0` on `Opened`, `1` on a C1 rejection (e.g. missing
file), and `2` for bad usage, no destination, protocol failure, or timeout. It
never starts a destination, tries another session, or retries after a failure.
A lost acknowledgement does not mean an open was not already applied.

## Selection and lifetime

* Roots are normalized lexically, using C1's semantics; e.g. `/work/demo/.` and
  `/work/demo` identify the same project. Symlink aliases are not resolved.
  Different effective users do not share an endpoint.
* The first opted-in session to acquire the project lock wins. A concurrent
  contender fails without displacing it. Only an explicit subsequent startup
  can acquire after exit; still-running non-selected editors are not promoted.
* This backend uses pathname Unix-domain sockets, advisory `flock` and
  hard links to socket nodes in `/tmp`. The runtime directory
  `/tmp/cobalt-main-v1-<effective-uid>` is checked for exact ownership and mode
  `0700`, and the lock and socket use `0600`. The directory must not be a
  symlink. Same-UID programs are in the same trust domain.
* The normalized root is checked in the ownership record and at dispatch; the
  hash only gives the project a short pathname. A key collision cannot route an
  open to the wrong project. The sender connects to the selected socket's
  generation-specific name so it doesn't silently reconnect to a replacement.
* Clean stop closes connections, unpublishes only the owned socket and releases
  the lock. After an unclean exit, a new opt-in only removes a stale publication
  if its recorded generation has a matching socket inode. Unexpected paths
  (including foreign socket nodes and symlinks) are left untouched, and startup
  fails closed. Ownership files remain deliberately; unlinking a lock file
  while processes may have it open lets contenders lock different inodes.
  A crash before publication can also leave an unused generation directory;
  it is never selected. Only remove runtime state manually when no Cobalt
  receivers or senders are using it.

## Standalone adapter

Use `Cobalt_main_editor` (`cobalt.main_editor` in Dune), only when the user
explicitly opts in. Its public `Open_location` records and variants mirror C1
without requiring an import of Cobalt's private app library. Pass the live
session's `Session.project_root` to `start`. Convert the callback's request at
the boundary to the editor's ordinary C1 handler and resolve `Ok ()` **after**
the editor adopted the new state, or `Error failure` when rejected. No buffer
IDs or editor state are exchanged. Do not call `Session.open_location` on a
snapshot captured when registering the callback. Call the idempotent `stop`
during teardown.

The transport allows at most one pending C1 callback per listener and rejects
additional requests while it is busy. It does not cancel an invoked callback
on sender disconnect or timeout; the owning adapter must prevent operations
from being applied after its own teardown. Keep callbacks nonblocking and
resolve them promptly. Socket handling remains off the render path.

The internal protocol accepts one versioned, size-bounded request per local
connection, with a half-close at the end of the request and a single typed
acknowledgement. It bounds the frame size (32 KiB), simultaneous connections
(8), read time (2 s), callback acknowledgement wait (3 s), and response write
time (1 s). The sender has a 1 s connect deadline and a 5 s exchange deadline.
Unsupported, malformed, oversized, partial or extra requests do not reach the
editor adapter. External OCaml callers should use `send`, not the internal wire
format.

```sh
dune runtest -j 4 main_editor
```

The transport tests use separate processes to check selection, C1 results,
unavailable endpoints, deadlines, shutdown/restart, and stale socket ownership
without a terminal or the editor UI.
