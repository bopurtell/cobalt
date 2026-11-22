open! Core
open! Async

module Pool = Cobalt_terminal_pool

type t = Pool.t

let create = Pool.create
let submit_sessions = Pool.submit
let next_session_update = Pool.next_update
let stop = Pool.stop
let shutdown = Pool.shutdown

let submit t requests = submit_sessions t (List.map requests ~f:(fun request -> 1, request))

let next_update t =
  let%map update = next_session_update t in
  Option.map update ~f:(fun (_, generation, event) -> generation, event)
;;

let next_event t =
  let%map update = next_update t in
  Option.map update ~f:snd
;;
