open! Core
open! Async

type t

val create : unit -> t
val stop : t -> unit
val execute : t -> Cobalt_app.Bsc.request -> Cobalt_app.Bsc.result Deferred.t
