open! Core
open Async
module Flow = Silver_flow
module Stage = Cobalt_screen.Silver_stage_tile
module Observation = Silver_stage_observation

type destination = { stage : Flow.stage; action : Stage.Action.t }

type t =
  { mutable next : int
  ; mutable revision : int option
  ; mutable destinations : destination list
  ; mutable empty : string
  ; mutable aliases : (Stage.Alias.t * Stage.Action.t) list
  ; mutable intents : (Stage.Intent.t * Flow.stage_intent) list
  }

let create () =
  { next = 0
  ; revision = None
  ; destinations = []
  ; empty = "Connect to a Silver project first"
  ; aliases = []
  ; intents = []
  }
;;

let summarize ({ target; flow; profile; endpoint; assignments } : Flow.inputs) =
  String.concat ~sep:" · "
    ([ "endpoint " ^ endpoint; flow ^ "/" ^ profile ]
     @ Option.to_list (Option.map target ~f:(fun target -> target.chip ^ "/" ^ target.variant))
     @ List.map assignments ~f:(fun (key, value) -> key ^ "=" ^ value))
;;

let update_launch t flow =
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
     (match Flow.catalog_view flow with
        | Error reason ->
          t.destinations <- [];
          t.aliases <- [];
          t.empty <- reason
        | Ok view ->
          t.destinations <- List.map (Flow.stages flow view) ~f:(fun (stage, result) ->
            { stage; action = action result });
          t.aliases <-
            List.map [ Stage.Alias.Synth, Flow.Synth; Timing, Timing; Routing, Routing ]
              ~f:(fun (alias, named) -> alias, action (Flow.resolve_alias flow view named));
          t.empty <-
            match (Flow.catalog view).stage_launch with
            | Unavailable reason -> reason
            | Available () ->
               Option.value (Flow.stage_selection_error flow view)
                 ~default:"Silver declared no stages for the active flow");
     t.intents <- !intents;
     t.revision <- Some revision)
;;

let label ~id name = if String.equal id "cts" then "cts" else name

let context (inputs : Flow.inputs) =
  String.concat ~sep:" · "
    ([ inputs.flow ^ "/" ^ inputs.profile ]
     @ Option.to_list (Option.map inputs.target ~f:(fun target -> target.chip ^ "/" ^ target.variant)))
;;

let active_inputs flow = Result.ok (Flow.catalog_view flow) |> Option.bind ~f:(Flow.active_inputs flow)

let scope (inputs : Flow.inputs) : Observation.selection =
  { target = inputs.target; flow = inputs.flow; profile = inputs.profile }
;;

let status : Observation.status -> Stage.Status.t = function
  | Pending -> Pending
  | Running -> Running
  | Cancelling -> Cancelling
  | Completed -> Completed
  | Failed -> Failed
  | Skipped -> Skipped
  | Cancelled -> Cancelled
  | Interrupted -> Interrupted
  | Not_requested -> Not_requested
  | Unsupported -> Unsupported
  | Unconfirmed | Unavailable -> Unknown
  | Unknown value -> Unrecognized value
;;

let destination_id id = "destination:" ^ id

let catalog_row { stage; action } : Stage.Row.t =
  { id = destination_id stage.id; label = label ~id:stage.id stage.label; status = Unknown; action }
;;

let observed_rows ~scope destinations (evidence : Observation.stage list) =
  let used = Hash_set.create (module String) in
  let duplicate =
    List.map evidence ~f:(fun stage -> stage.id)
    |> List.find_all_dups ~compare:String.compare
    |> String.Set.of_list
  in
  let destination (stage : Observation.stage) =
    match stage.origin with
    | Physical when not (Set.mem duplicate stage.id) ->
      let candidates =
        List.filter destinations ~f:(fun { stage = candidate; _ } ->
          match stage.launch_destination with
          | None -> String.equal candidate.id stage.id
          | Some (reported_scope, endpoint) ->
            Option.exists scope ~f:(Poly.equal reported_scope)
            && (match candidate.endpoint with
                | Available allowed -> String.equal allowed endpoint
                | Unavailable _ -> false))
      in
      (match candidates with [ candidate ] -> Some candidate | _ -> None)
    | _ -> None
  in
  let claimed_twice =
    List.filter_map evidence ~f:(fun stage ->
      Option.map (destination stage) ~f:(fun { stage; _ } -> stage.id))
    |> List.find_all_dups ~compare:String.compare
    |> String.Set.of_list
  in
  let observed =
    List.filter_map evidence ~f:(fun stage ->
      match stage.origin with
      | Requested_endpoint -> None
      | _ ->
        let ambiguous = Set.mem duplicate stage.id in
        let destination = Option.filter (destination stage) ~f:(fun { stage; _ } ->
          not (Set.mem claimed_twice stage.id)) in
        let id, action =
          match destination with
          | Some { stage; action } -> destination_id stage.id, action
          | None ->
            "evidence:" ^ stage.id,
            Stage.Action.Blocked "This stage is not a fresh launch destination"
        in
        if Hash_set.mem used id then None
        else (
          Hash_set.add used id;
          let name =
            match stage.origin with
            | Supplementary_timing -> "Timing analysis"
            | _ -> label ~id:stage.id stage.label
          in
          Some ({ id; label = name
                ; status = (if ambiguous then Unknown else status stage.status)
                ; action } : Stage.Row.t)))
  in
  let remaining =
    List.filter destinations ~f:(fun { stage; _ } ->
      not (Hash_set.mem used (destination_id stage.id))
      && (List.is_empty observed || (match stage.endpoint with Available _ -> true | _ -> false)))
  in
  observed @ List.map remaining ~f:catalog_row
;;

let watch_context ~pin (observation : Observation.availability) =
  match pin, observation with
  | Some id, Fresh { run_id = Some _; _ } -> "Pinned ASIC run " ^ id
  | Some id, _ -> "Pinned ASIC run " ^ id ^ " (progress unavailable)"
  | None, Fresh { run_id = Some id; _ } -> "Latest ASIC run " ^ id
  | None, Fresh { workflow_id = Some id; _ } -> "Latest ASIC workflow " ^ id
  | None, Fresh { notice = Some notice; _ } -> notice
  | None, Stale _ -> "ASIC progress stale"
  | None, (Fresh _ | Not_available _) -> "Following latest ASIC run"
;;

let snapshot t flow ~(observation : Observation.availability) ~pin =
  update_launch t flow;
  let inputs = active_inputs flow in
  let evidence =
    match observation with
    | Observation.Fresh snapshot -> snapshot.stages
    | Stale _ | Not_available _ -> []
  in
  { Stage.Snapshot.rows = observed_rows ~scope:(Option.map inputs ~f:scope) t.destinations evidence
  ; empty = t.empty
  ; aliases = t.aliases
  ; context = Option.map inputs ~f:context
  ; watch_context = Option.map inputs ~f:(fun _ -> watch_context ~pin observation)
  }
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
