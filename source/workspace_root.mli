(** Where a diagnostic source is started for a document. *)
open! Core

(** The root for [path] by Neovim's [vim.fs.root] rule: each marker in [markers] in turn
    is looked for in [path]'s directory and then each ancestor's, and the first marker
    found anywhere wins, at its nearest directory. Markers are literal file or directory
    names (as in Neovim, ["*.opam"] matches only that name). The result is absolute;
    [path]'s directory itself when no marker is found or it cannot be resolved. *)
val find_first : markers:string list -> string -> string

(** Searches directories nearest first, accepting any literal marker. *)
val find_nearest : markers:string list -> string -> string

(** [find_first ~markers:["dune-project"]]: the synthetic checker's root. *)
val find : string -> string

(** Nearest Cargo manifest, if present. *)
val cargo_manifest : string -> string option

(** Asynchronously ask Cargo which workspace owns this absolute manifest. Returns
    [None] if Cargo cannot resolve it (including toolchain errors and timeout).
    Does not fetch dependencies or build the project. *)
val cargo_workspace : string -> string option Async.Deferred.t
