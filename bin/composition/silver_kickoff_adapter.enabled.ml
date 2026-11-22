open! Core
open Async
module Flow = Silver_flow
module Host = Cobalt_ui.Silver_kickoff_host
module Tile = Cobalt_screen.Silver_kickoff_tile

type draft =
  { token : int
  ; value : Flow.draft
  }

type delivery =
  | Idle
  | Pending of string
  | Finished of string * Flow.outcome

type t =
  { flow : Flow.t
  ; changed : unit -> unit
  ; project_root : unit -> string option
  ; fresh_token : unit -> int
  ; mutable catalog : (int * Flow.view) option
  ; mutable draft : draft option
  ; mutable ready : (int * Flow.ready) option
  ; mutable problem : string option
  ; mutable selection_problem : string option
  ; mutable delivery : delivery
  }

let live_catalog t =
  (* The shared session caches one view object per catalog generation. The
     frontend token lets the form capture it without depending on Silver types. *)
  let invalidate () =
    if Option.is_some t.draft || Option.is_some t.ready then
      t.problem <- Some "Flow catalog changed; apply the inputs and prepare a new preview";
    t.draft <- None;
    t.ready <- None;
    t.selection_problem <- None
  in
  match Flow.catalog_view t.flow with
  | Error reason ->
    invalidate ();
    t.catalog <- None;
    Error reason
  | Ok view ->
    (match t.catalog with
     | Some (token, previous) when phys_equal previous view -> Ok (token, view)
     | _ ->
       invalidate ();
       let token = t.fresh_token () in
       t.catalog <- Some (token, view);
       Ok (token, view))
;;

let parameter_label ({ key; label; _ } : Flow.parameter) =
  if String.equal key label then "Parameter " ^ key
  else sprintf "Parameter %s (%s)" key label
;;

let with_choices label choices =
  if List.is_empty choices then label
  else sprintf "%s [%s]" label (String.concat ~sep:" / " choices)
;;

let profile_name (flow : Flow.flow) = with_choices "Profile" flow.profiles
let endpoint_name (schema : Flow.schema) = with_choices "Endpoint" schema.endpoints
let parameter_name (parameter : Flow.parameter) =
  with_choices (parameter_label parameter) parameter.choices
;;

let fields flow (schema : Flow.schema) (i : Flow.inputs) =
  [ profile_name flow, i.profile; endpoint_name schema, i.endpoint ]
  @ List.map schema.parameters ~f:(fun parameter ->
    let value =
      List.Assoc.find i.assignments parameter.key ~equal:String.equal
      |> Option.value ~default:""
    in
    parameter_name parameter, value)
;;

let choices t token view =
  List.partition_map (Flow.catalog view).flows ~f:(fun (flow : Flow.flow) ->
    let unavailable reason = Second (sprintf "%s unavailable: %s" flow.label reason) in
    match flow.kickoff with
    | Unavailable reason -> unavailable reason
    | Available schema ->
      (match Flow.draft t.flow view ~flow:flow.id with
       | Error reason -> unavailable reason
       | Ok draft ->
         First
           { Tile.Target.id = flow.id
           ; label = flow.label
           ; catalog = token
           ; fields = fields flow schema (Flow.draft_inputs draft)
           }))
;;

let target_name = function
  | Some ({ chip; variant } : Flow.target) -> chip ^ " / " ^ variant
  | None -> "not specified by Silver"
;;

let input_rows (inputs : Flow.inputs) =
  [ "Chip / variant: " ^ target_name inputs.target
  ; "Flow: " ^ inputs.flow
  ; "Profile: " ^ inputs.profile
  ; "Endpoint: " ^ inputs.endpoint
  ]
  @ (match inputs.assignments with
     | [] -> [ "Parameters: none" ]
     | values -> List.map values ~f:(fun (key, value) -> sprintf "Parameter %s = %s" key value))
;;

let outcome_text = function
  | Flow.Accepted (Run id) -> "Accepted · run " ^ id
  | Accepted (Workflow { workflow_id; run_id }) ->
    "Accepted · workflow " ^ workflow_id
    ^ Option.value_map run_id ~default:"" ~f:(fun id -> " · run " ^ id)
  | Rejected reason -> "Rejected: " ^ reason
  | Stale reason -> "Preview stale: " ^ reason
  | Unconfirmed reason -> "Delivery unconfirmed: " ^ reason
;;

let delivery_rows = function
  | Idle -> []
  | Pending label -> [ "Submission pending · " ^ label ]
  | Finished (label, outcome) -> [ outcome_text outcome ^ " · " ^ label ]
;;

let ready t value =
  (* Tokenize the ready object, not its display ID. Two preparations may return
     the same plan ID without making a queued action from the first one valid. *)
  match t.ready with
  | Some (token, previous) when phys_equal previous value -> token
  | _ ->
    let token = t.fresh_token () in
    t.ready <- Some (token, value);
    token
;;

let presentation t =
  let safe = [ "Uses saved Silver project inputs; Cobalt does not save your buffer." ] in
  let project = Option.to_list (Option.map (t.project_root ()) ~f:(( ^ ) "Project: ")) in
  let delivery = delivery_rows t.delivery in
  match live_catalog t with
  | Error reason ->
    let initial = Tile.Presentation.unavailable reason in
    { initial with details = delivery @ project @ Option.to_list t.problem @ safe }
  | Ok (token, view) ->
    let targets, unavailable = choices t token view in
    let choices =
      List.map (Flow.catalog view).flows ~f:(fun (flow : Flow.flow) ->
        { Tile.Choice.id = flow.id; label = flow.label; catalog = token })
    in
    let selected = Flow.selected_flow t.flow view in
    let active = Flow.active_flow t.flow view in
    let notice =
      match t.selection_problem, selected, active with
      | Some reason, _, _ -> Some reason
      | None, Some _, None -> Some "Silver flow inputs changed; select a named flow again"
      | _ -> None
    in
    let problem = Option.to_list t.problem in
    let draft =
      match t.draft with
      | None -> Error "Choose a named flow and apply its inputs"
      | Some draft -> Ok draft.token
    in
    let preparation = Flow.preparation t.flow in
    let kickoff, preview =
      match preparation with
      | Flow.Not_prepared reason -> Error reason, []
      | Preparing -> Error "Preview preparation pending", []
      | Ready value ->
        let preview = Flow.preview value in
        Ok (ready t value), ("Reviewed preview: " ^ preview.identity) :: input_rows preview.inputs
    in
    let draft, kickoff =
      match preparation, t.delivery, Flow.submission t.flow with
      | _, Pending _, _ | _, _, Pending _ ->
        Error "Submission acknowledgement pending", Error "Submission acknowledgement pending"
      | Preparing, _, _ -> Error "Preview preparation pending", kickoff
      | _ when Option.is_some t.problem ->
        draft, Error (Option.value_exn t.problem)
      | _ -> draft, kickoff
    in
    let draft_details =
      match t.draft, preview with
      | Some draft, [] -> "Applied draft (not a preview)" :: input_rows (Flow.draft_inputs draft.value)
      | _ -> []
    in
    { Tile.Presentation.choices
    ; selected
    ; active
    ; notice
    ; targets
    ; draft
    ; kickoff
    ; details = problem @ project @ preview @ delivery @ draft_details @ unavailable @ safe
    }
;;

let apply t (target : Tile.Target.t) values =
  let open Result.Let_syntax in
  let%bind token, view = live_catalog t in
  let%bind () =
    if token = target.catalog then Ok ()
    else Error "Flow catalog changed while editing; select the flow again"
  in
  let%bind flow =
    List.find (Flow.catalog view).flows ~f:(fun (flow : Flow.flow) ->
      String.equal target.id flow.id)
    |> Result.of_option ~error:"The selected flow is no longer declared"
  in
  let%bind schema =
    match flow.kickoff with Available schema -> Ok schema | Unavailable reason -> Error reason
  in
  let%bind draft = Flow.draft t.flow view ~flow:flow.id in
  let prior = Flow.draft_inputs draft in
  let%bind () =
    if [%equal: (string * string) list] (fields flow schema prior) target.fields
       && [%equal: string list] (List.map values ~f:fst) (List.map target.fields ~f:fst)
    then Ok ()
    else Error "Flow inputs changed while editing; reopen the form"
  in
  let find name = List.Assoc.find_exn values name ~equal:String.equal in
  let assignments =
    List.filter_map schema.parameters ~f:(fun parameter ->
      let value = find (parameter_name parameter) in
      if String.is_empty value
         && not (Option.equal String.equal parameter.default (Some ""))
         && not (List.mem parameter.choices "" ~equal:String.equal)
      then None
      else Some (parameter.key, value))
  in
  let draft =
    Flow.edit draft
      { prior with profile = find (profile_name flow); endpoint = find (endpoint_name schema); assignments }
  in
  let%map () = Flow.apply t.flow draft in
  t.draft <- Some { token = t.fresh_token (); value = draft };
  t.ready <- None
;;

let dispatch t intent =
  let fail reason =
    t.problem <- Some reason;
    t.changed ();
    false
  in
  match (intent : Tile.Intent.t) with
  | Select choice ->
    let before = Flow.revision t.flow in
    let result =
      let open Result.Let_syntax in
      let%bind token, view = live_catalog t in
      let%bind () =
        if token = choice.catalog then Ok ()
        else Error "Silver flow catalog changed; select the flow again"
      in
      Flow.select_flow t.flow view ~flow:choice.id
    in
    let selected = before <> Flow.revision t.flow in
    if selected then (
      t.draft <- None;
      t.ready <- None);
    (match result with
     | Ok () ->
       t.selection_problem <- None;
       if selected then t.problem <- None;
       t.changed ();
       selected
     | Error reason ->
       t.selection_problem <- Some reason;
       t.changed ();
       false)
  | Apply (target, values) ->
    (match apply t target values with
     | Error reason -> fail reason
     | Ok () ->
       t.problem <- None;
       t.selection_problem <- None;
       t.changed ();
       false)
  | Prepare token ->
    let shown = presentation t in
    (match shown.draft with
     | Ok current when current = token ->
       t.problem <- None;
        t.ready <- None;
        don't_wait_for (Flow.prepare t.flow >>| t.changed);
        t.changed ();
        false
     | Error reason -> fail reason
     | Ok _ -> fail "Flow draft changed; apply the inputs again")
  | Kickoff token ->
    let shown = presentation t in
    (match shown.kickoff, t.ready with
     | Ok current, Some (_, value) when current = token ->
       let preview = Flow.preview value in
       let label =
         preview.inputs.flow ^ " / " ^ preview.identity
         ^ Option.value_map (t.project_root ()) ~default:"" ~f:(( ^ ) " · project ")
       in
       t.problem <- None;
       t.ready <- None;
       t.delivery <- Pending label;
       (* The pending reply lives here, not in the tile placement. The shared
          session revalidates and consumes the exact ready value before sending. *)
       don't_wait_for
          (Flow.kickoff t.flow value >>| fun outcome ->
           t.delivery <- Finished (label, outcome);
           t.changed ());
        t.changed ();
        false
     | Error reason, _ -> fail reason
     | Ok _, _ -> fail "Reviewed preview changed; review the new preview before Kickoff")
;;

let create ~flow ~changed ~project_root : Host.t =
  let serial = ref 0 in
  let fresh_token () = incr serial; !serial in
  let t =
    { flow; changed; project_root; fresh_token; catalog = None; draft = None
    ; ready = None; problem = None; selection_problem = None; delivery = Idle
    }
  in
  { presentation = (fun () -> presentation t); dispatch = dispatch t }
;;
