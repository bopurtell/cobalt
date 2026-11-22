open! Core
open Async

module Overview = Silver_overview

let json_option f = function
  | None -> `Null
  | Some value -> f value
;;

let str value = `String value

let snapshot_json ({ binding; instance_id; project_id; attempts; truncated } : Overview.snapshot)
  =
  let attempt_json ({ id; suite; lifecycle; outcome } : Overview.attempt) =
    `Assoc
      [ "id", str id
      ; "suite", str suite
      ; "lifecycle", str lifecycle
      ; "outcome", json_option str outcome
      ]
  in
  [ "endpoint", str binding.endpoint
  ; "root", str binding.project_root
  ; "run", json_option str binding.run
  ; "instance", str instance_id
  ; "project", str project_id
  ; "attempts", `List (List.map attempts ~f:attempt_json)
  ; "truncated", `Bool truncated
  ]
;;

let print t =
  let availability =
    match Overview.latest t with
    | Unavailable reason -> [ "state", str "unavailable"; "reason", str reason ]
    | Fresh snapshot -> ("state", str "fresh") :: snapshot_json snapshot
    | Stale (snapshot, reason) ->
      ("state", str "stale") :: ("reason", str reason) :: snapshot_json snapshot
  in
  printf "%s\n%!" (Yojson.Safe.to_string (`Assoc availability))
;;

let span ms = Time_ns.Span.of_int_ms ms

let () =
  let endpoint = (Sys.get_argv ()).(1) in
  let t =
    Overview.create
      ~timeout:(span 700)
      ~poll_interval:(span 250)
      ~retry_initial:(span 100)
      ~retry_max:(span 100)
      ()
  in
  let rec drive () =
    match%bind Reader.read_line (Lazy.force Reader.stdin) with
    | `Eof ->
      Overview.shutdown t;
      Shutdown.shutdown 0;
      Deferred.unit
    | `Ok line ->
      (match String.split line ~on:'\t' with
       | [ "bind"; project_root; run ] ->
         let run = if String.is_empty run then None else Some run in
         Overview.rebind t { endpoint; project_root; run }
       | [ "read" ] -> ()
       | [ "close" ] -> Overview.unbind t
       | [ "shutdown" ] -> Overview.shutdown t
       | _ -> failwithf "Unknown driver control: %S" line ());
      print t;
      drive ()
  in
  don't_wait_for (drive ());
  never_returns (Scheduler.go ())
;;
