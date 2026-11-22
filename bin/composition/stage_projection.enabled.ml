open! Core
open Async
module Flow = Silver_flow
module Stage = Cobalt_screen.Silver_stage_tile

type t =
  { mutable next : int
  ; mutable revision : int option
  ; mutable snapshot : Stage.Snapshot.t
   ; mutable intents : (Stage.Intent.t * Flow.stage_intent) list
  }

let create () =
  { next = 0
  ; revision = None
  ; snapshot = Stage.Snapshot.unavailable "Connect to a Silver project first"
  ; intents = []
  }
;;

let summarize ({ target; flow; profile; endpoint; assignments } : Flow.inputs) =
  String.concat ~sep:" · "
    ([ "endpoint " ^ endpoint; flow ^ "/" ^ profile ]
     @ Option.to_list (Option.map target ~f:(fun target -> target.chip ^ "/" ^ target.variant))
     @ List.map assignments ~f:(fun (key, value) -> key ^ "=" ^ value))
;;

let snapshot t flow =
  let revision = Flow.revision flow in
  if not (Option.equal Int.equal t.revision (Some revision)) then (
    let intents = ref [] in
    let action = function
      | Error reason -> Stage.Action.Blocked reason
      | Ok intent ->
         let projected =
           let matching compare =
             List.find ~f:(fun (_, candidate) -> compare candidate intent)
           in
           let matching_intent = matching Flow.equal_stage_intent in
           match matching_intent !intents with
           | Some (projected, _) -> projected
           | None ->
             let projected =
               match matching_intent t.intents with
               | Some (projected, _) -> projected
               | None ->
                 t.next <- t.next + 1;
                 let token = Int.to_string t.next in
                 let selection =
                   match matching Flow.equal_stage_selection t.intents with
                   | Some (previous, _) -> previous.selection
                   | None -> token
                 in
                 { Stage.Intent.token; selection; summary = summarize (Flow.stage_inputs intent) }
             in
             intents := (projected, intent) :: !intents;
             projected
         in
         Stage.Action.Ready projected
    in
    t.snapshot <-
      (match Flow.catalog_view flow with
       | Error reason -> Stage.Snapshot.unavailable reason
       | Ok view ->
         let rows = List.map (Flow.stages flow view) ~f:(fun (stage, result) : Stage.Row.t ->
           { id = stage.id; label = stage.label; action = action result })
         in
         let aliases =
           List.map [ Stage.Alias.Synth, Flow.Synth; Timing, Timing; Routing, Routing ]
             ~f:(fun (alias, named) -> alias, action (Flow.resolve_alias flow view named))
         in
         let empty =
           match (Flow.catalog view).stage_launch with
           | Unavailable reason -> reason
           | Available () ->
             (match (Flow.catalog view).default_flow with
              | None -> "No declared Silver default flow/profile; choose explicit inputs"
              | Some _ -> "Silver declared no stages for the active flow")
         in
         { rows; aliases; empty });
    t.intents <- !intents;
    t.revision <- Some revision);
  t.snapshot
;;

let launch t flow (captured : Stage.Intent.t) =
  match List.find_map t.intents ~f:(fun (projected, intent) ->
    Option.some_if (Stage.Intent.equal captured projected) intent) with
  | None -> return (Error "Silver stage selection changed; select a stage again; nothing ran")
  | Some intent ->
    Flow.launch_stage flow intent >>| fun outcome ->
    let display status = sprintf "Silver stage · %s · %s" status captured.summary in
    match outcome with
    | Accepted (Run run) -> Ok (display ("Accepted · run " ^ run))
    | Accepted (Workflow { workflow_id; run_id }) ->
      Ok (display (sprintf "Accepted · workflow %s%s" workflow_id
        (Option.value_map run_id ~default:"" ~f:(sprintf " · run %s"))))
    | Rejected reason -> Error (display ("Rejected: " ^ reason))
    | Stale reason -> Error (display ("Stale; reselect a stage: " ^ reason))
    | Unconfirmed reason -> Error (display ("Delivery unconfirmed: " ^ reason))
;;
