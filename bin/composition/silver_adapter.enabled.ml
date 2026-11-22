open! Core
module Host = Cobalt_ui.Silver_overview_host
module Adapter = Silver_overview

let attempt_rows ({ id; suite; lifecycle; outcome } : Adapter.attempt) =
  [ "Lifecycle: " ^ lifecycle
  ; "Outcome: " ^ Option.value outcome ~default:"Unknown"
  ; "Suite: " ^ suite
  ; "Attempt: " ^ id
  ]
;;

let rows (binding : Host.binding) availability =
  let status, snapshot, reason =
    match availability with
    | Adapter.Unavailable reason -> "Unavailable", None, Some reason
    | Fresh snapshot -> "Fresh", Some snapshot, None
    | Stale (snapshot, reason) -> "Stale", Some snapshot, Some reason
  in
  [ "Status: " ^ status; "Project: " ^ binding.project_root; "Run: " ^ binding.run ]
  @ Option.value_map snapshot ~default:[] ~f:(fun snapshot ->
      List.concat_map snapshot.attempts ~f:attempt_rows
      @ (if snapshot.truncated then [ "More attempts omitted" ] else []))
  @ [ "Endpoint: " ^ binding.endpoint ]
  @ Option.value_map reason ~default:[] ~f:(fun reason -> [ reason ])
;;

let factory : Host.factory =
  Some (fun (binding : Host.binding) ->
    let adapter = Adapter.create () in
    let show () =
      Adapter.rebind adapter
        { endpoint = binding.endpoint; project_root = binding.project_root; run = Some binding.run }
    in
    { Host.rows = (fun () -> rows binding (Adapter.latest adapter))
    ; show
    ; hide = (fun () -> Adapter.unbind adapter)
    ; refresh = show
    ; revision = (fun () -> Adapter.revision adapter)
    ; await_change = (fun ~after -> Adapter.await_change adapter ~after)
    ; shutdown = (fun () -> Adapter.shutdown adapter)
    })
;;
