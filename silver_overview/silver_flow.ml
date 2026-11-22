open! Core
open Async

type binding =
  { endpoint : string
  ; project_root : string
  ; instance_id : string
  ; project_id : string
  }

type target = { chip : string; variant : string } [@@deriving equal]

type inputs =
  { target : target option
  ; flow : string
  ; profile : string
  ; endpoint : string
  ; assignments : (string * string) list
  }
[@@deriving equal]

type parameter =
  { key : string
  ; label : string
  ; default : string option
  ; choices : string list
  }

type 'a availability = Available of 'a | Unavailable of string
type alias = Synth | Timing | Routing [@@deriving equal]
type stage =
  { id : string
  ; label : string
  ; alias : alias option
  ; endpoint : string availability
  }
type schema =
  { endpoints : string list
  ; default_endpoint : string option
  ; parameters : parameter list
  }
type flow =
  { id : string
  ; label : string
  ; profiles : string list
  ; default_profile : string
  ; stages : stage list
  ; kickoff : schema availability
  }
type catalog =
  { target : target option
  ; flows : flow list
  ; default_flow : (string * string) option
  ; stage_launch : unit availability
  }

type accepted = Run of string | Workflow of { workflow_id : string; run_id : string option }
type outcome = Accepted of accepted | Rejected of string | Stale of string | Unconfirmed of string
type preview = { identity : string; inputs : inputs }
type request = Stage of inputs | Kickoff of inputs
type prepared = { preview : preview; submit : still_current:(unit -> bool) -> outcome Deferred.t }
type service =
  { binding : binding
  ; catalog : unit -> (catalog, string) result Deferred.t
  ; prepare : request -> (prepared, string) result Deferred.t
  }

type view = { owner : unit ref; generation : int; catalog : catalog }
type stage_intent = { view : view; settings : int; inputs : inputs }
type draft = { view : view; flow : string; inputs : inputs; defaults : (string * string) list }
type ready = { draft : draft; prepared : prepared }
type preparation = Not_prepared of string | Preparing | Ready of ready
type submission = Idle | Pending of inputs | Finished of inputs * outcome

type t =
  { owner : unit ref
  ; mutable service : service option
  ; mutable binding_serial : int
  ; mutable generation : int
  ; mutable settings : int
  ; mutable stage_settings : (view * inputs) option
  ; mutable catalog_view : (view, string) result
  ; mutable draft : draft option
  ; mutable plan_serial : int
  ; mutable preparation : preparation
  ; mutable submission : submission
  ; mutable revision : int
  ; mutable changed : unit Ivar.t
  }

let no_binding = "Connect to a Silver project first"
let stale_catalog = "Silver flow catalog changed; reselect inputs"
let stale_preview = "Silver flow preview changed; prepare again"
let pending = "A Silver flow launch acknowledgement is pending"

let create () =
  { owner = ref (); service = None; binding_serial = 0; generation = 0
  ; settings = 0; stage_settings = None; catalog_view = Error no_binding; draft = None
  ; plan_serial = 0; preparation = Not_prepared no_binding; submission = Idle
  ; revision = 0; changed = Ivar.create ()
  }
;;

let touch t =
  t.revision <- t.revision + 1;
  Ivar.fill_if_empty t.changed ();
  t.changed <- Ivar.create ()
;;

let revision t = t.revision
let await_change t ~after = if after <> t.revision then Deferred.unit else Ivar.read t.changed
let catalog_view t = t.catalog_view
let catalog (view : view) = view.catalog
let stage_inputs (intent : stage_intent) = intent.inputs
let equal_stage_selection (a : stage_intent) (b : stage_intent) =
  phys_equal a.view b.view && equal_inputs a.inputs b.inputs
;;

let equal_stage_intent (a : stage_intent) (b : stage_intent) =
  a.settings = b.settings && equal_stage_selection a b
;;
let draft_inputs (draft : draft) = draft.inputs
let preview (ready : ready) = ready.prepared.preview
let preparation t = t.preparation
let submission t = t.submission

let reset_plan t reason =
  t.plan_serial <- t.plan_serial + 1;
  t.preparation <- Not_prepared reason
;;

let invalidate t reason =
  t.generation <- t.generation + 1;
  t.catalog_view <- Error reason;
  t.draft <- None;
  reset_plan t reason
;;

let rebind t service =
  t.binding_serial <- t.binding_serial + 1;
  t.service <- service;
  t.stage_settings <- None;
  t.submission <- Idle;
  invalidate t (if Option.is_some service then "Load the Silver flow catalog first" else no_binding);
  touch t
;;

let bind t service = rebind t (Some service)
let unbind t = rebind t None
let refresh t =
  match t.service with
  | None -> Deferred.unit
  | Some service ->
    invalidate t "Loading Silver flow catalog…";
    let generation = t.generation in
    touch t;
    let%map result = Monitor.try_with (fun () -> service.catalog ()) in
    if generation = t.generation then (
      let message = "Could not load Silver flow catalog" in
      t.catalog_view <-
        (match result with
         | Ok (Ok catalog) -> Ok { owner = t.owner; generation; catalog }
         | Ok (Error reason) -> Error reason
         | Error _ -> Error message);
      reset_plan t (match t.catalog_view with Ok _ -> "Choose flow inputs" | Error reason -> reason);
      touch t)
;;

let require condition reason = if condition then Ok () else Error reason
let some value reason = Option.value_map value ~default:(Error reason) ~f:Result.return
let available = function Available value -> Ok value | Unavailable reason -> Error reason
let current (t : t) (view : view) = phys_equal t.owner view.owner && t.generation = view.generation
let check_view t view = require (current t view) stale_catalog
let find_flow (catalog : catalog) id =
  some (List.find catalog.flows ~f:(fun f -> String.equal f.id id))
    ("Silver flow is unavailable: " ^ id)
;;

let check_assignments ~parameters assignments =
  let open Result.Let_syntax in
  let keys = List.map assignments ~f:fst in
  let%bind () =
    require (not (List.contains_dup keys ~compare:String.compare)) "Duplicate parameter assignment"
  in
  List.fold_result assignments ~init:() ~f:(fun () (key, value) ->
    let%bind () =
      require (not (String.is_empty key || String.contains key '=' || String.contains key '\000'
                    || String.contains value '\000'))
        "Invalid Silver parameter assignment"
    in
    match parameters with
    | None -> Ok ()
    | Some parameters ->
      let%bind parameter =
        some (List.find parameters ~f:(fun p -> String.equal p.key key))
          ("Undeclared Silver parameter: " ^ key)
      in
      require (List.is_empty parameter.choices || List.mem parameter.choices value ~equal:String.equal)
        ("Invalid value for Silver parameter: " ^ key))
;;

let check_selection catalog (inputs : inputs) =
  let open Result.Let_syntax in
  let%bind () = require (Option.equal equal_target catalog.target inputs.target) "Silver chip/variant changed" in
  let%bind flow = find_flow catalog inputs.flow in
  let%bind () =
    require (List.mem flow.profiles inputs.profile ~equal:String.equal)
      ("Silver profile is unavailable: " ^ inputs.profile)
  in
  let parameters = match flow.kickoff with Available schema -> Some schema.parameters | Unavailable _ -> None in
  let%map () = check_assignments ~parameters inputs.assignments in
  flow
;;

let set_stage_inputs t view inputs =
  Result.map (check_view t view) ~f:(fun () ->
    t.settings <- t.settings + 1;
    t.stage_settings <- Option.map inputs ~f:(fun values -> view, values);
    touch t)
;;

let stage_selection t view =
  let open Result.Let_syntax in
  let%bind () = check_view t view in
  let%bind inputs =
    match t.stage_settings with
    | Some (original, inputs) ->
      let%map () = require (current t original) "Explicit Silver stage inputs are stale; reselect them" in
      inputs
    | None ->
      let%map flow, profile =
        some view.catalog.default_flow "No declared Silver default flow/profile; choose explicit inputs"
      in
      { target = view.catalog.target; flow; profile; endpoint = ""; assignments = [] }
  in
  let%map flow = check_selection view.catalog inputs in
  inputs, flow
;;

let resolve t view (inputs : inputs) (stage : stage) =
  let open Result.Let_syntax in
  let%bind () = available view.catalog.stage_launch in
  let%map endpoint = available stage.endpoint in
  { view; settings = t.settings; inputs = { inputs with endpoint } }
;;

let stages t view =
  match stage_selection t view with
  | Ok (inputs, flow) -> List.map flow.stages ~f:(fun stage -> stage, resolve t view inputs stage)
  | Error reason ->
    (* Retain the rows for the chosen flow when possible, but never retarget. *)
    let id =
      match t.stage_settings with
      | Some (_, inputs) -> Some inputs.flow
      | None -> Option.map view.catalog.default_flow ~f:fst
    in
    Option.bind id ~f:(fun id -> Result.ok (find_flow view.catalog id))
    |> Option.value_map ~default:[] ~f:(fun flow ->
      List.map flow.stages ~f:(fun stage -> stage, Error reason))
;;

let resolve_matching t view f reason =
  let open Result.Let_syntax in
  let%bind inputs, flow = stage_selection t view in
  let%bind () = available view.catalog.stage_launch in
  match List.filter flow.stages ~f with
  | [ stage ] -> resolve t view inputs stage
  | [] -> Error reason
  | _ -> Error "Silver advertised an ambiguous stage"
;;

let resolve_stage t view ~id =
  resolve_matching t view (fun (s : stage) -> String.equal s.id id)
    ("Silver stage is unavailable: " ^ id)
;;

let resolve_alias t view alias =
  resolve_matching t view (fun s -> Option.equal equal_alias s.alias (Some alias))
    "This named stage is not advertised for the selected Silver flow"
;;

let draft t view ~flow =
  let open Result.Let_syntax in
  let%bind () = check_view t view in
  let%bind entry = find_flow view.catalog flow in
  let%map schema = available entry.kickoff in
  let inputs : inputs =
    { target = view.catalog.target
    ; flow
    ; profile = entry.default_profile
    ; endpoint = Option.value schema.default_endpoint ~default:""
    ; assignments = List.filter_map schema.parameters ~f:(fun p ->
        Option.map p.default ~f:(fun value -> p.key, value))
    }
  in
  { view; flow; inputs; defaults = inputs.assignments }
;;

let edit (draft : draft) inputs = { draft with inputs }
let explicit_inputs (draft : draft) =
  { draft.inputs with
    assignments = List.filter draft.inputs.assignments ~f:(fun (key, value) ->
      not (Option.equal String.equal (List.Assoc.find draft.defaults key ~equal:String.equal) (Some value)))
  }
;;

let apply t (draft : draft) =
  let open Result.Let_syntax in
  let { view; inputs; _ } = draft in
  let%bind () = check_view t view in
  let%bind () = require (String.equal inputs.flow draft.flow) "Choose a new draft for a different flow" in
  let%bind entry = check_selection view.catalog inputs in
  let%bind schema = available entry.kickoff in
  let%map () =
    require (List.mem schema.endpoints inputs.endpoint ~equal:String.equal)
      "Choose an advertised Silver flow endpoint"
  in
  t.draft <- Some draft;
  t.settings <- t.settings + 1;
  t.stage_settings <- Some (view, explicit_inputs draft);
  reset_plan t "Prepare the edited inputs before Kickoff";
  touch t
;;

let same_selection (a : inputs) (b : inputs) = equal_inputs { a with assignments = [] } { b with assignments = [] }

let prepare t =
  match t.service, t.draft, t.preparation with
  | Some service, Some draft, (Not_prepared _ | Ready _) ->
    reset_plan t "Preparing Silver flow preview…";
    t.preparation <- Preparing;
    let serial = t.plan_serial in
    touch t;
    let inputs = explicit_inputs draft in
    let%map result = Monitor.try_with (fun () -> service.prepare (Kickoff inputs)) in
    if serial = t.plan_serial then (
      t.preparation <-
        (match result with
         | Ok (Ok prepared)
           when not (String.is_empty prepared.preview.identity)
                && same_selection prepared.preview.inputs draft.inputs ->
           Ready { draft; prepared }
         | Ok (Ok _) -> Not_prepared "Silver returned a different flow preview"
         | Ok (Error reason) -> Not_prepared reason
         | Error _ -> Not_prepared "Could not prepare Silver flow preview");
      touch t)
  | _ -> Deferred.unit
;;

let is_pending t = match t.submission with Pending _ -> true | _ -> false
let finish t ~binding_serial ~generation inputs outcome =
  if binding_serial = t.binding_serial then (
    (match outcome with
     | Stale reason when generation = t.generation -> invalidate t reason
     | _ -> ());
    t.submission <- Finished (inputs, outcome);
    touch t);
  outcome
;;

let send prepared ~still_current =
  Monitor.try_with (fun () -> prepared.submit ~still_current) >>| function
  | Ok outcome -> outcome
  | Error _ -> Unconfirmed "Silver launch acknowledgement unavailable"
;;

let launch_stage t (intent : stage_intent) =
  let current () = current t intent.view && t.settings = intent.settings in
  match t.service with
  | _ when not (current ()) -> return (Stale stale_catalog)
  | _ when is_pending t -> return (Rejected pending)
  | None -> return (Rejected no_binding)
  | Some service ->
    let binding_serial = t.binding_serial in
    t.submission <- Pending intent.inputs;
    touch t;
    let%bind result = Monitor.try_with (fun () -> service.prepare (Stage intent.inputs)) in
    let%map outcome =
      if not (current ()) then return (Stale "Silver stage inputs changed before submission")
      else
        match result with
        | Ok (Ok prepared)
          when not (String.is_empty prepared.preview.identity)
                && equal_inputs prepared.preview.inputs intent.inputs -> send prepared ~still_current:current
        | Ok (Ok _) -> return (Rejected "Silver staged different launch inputs")
        | Ok (Error reason) -> return (Rejected reason)
        | Error _ -> return (Rejected "Could not stage Silver flow inputs")
    in
    let generation =
      if current () then (
        (* A rendered action is single-use; a subsequent explicit launch must
           capture a newly rendered action, never replay this intent. *)
        t.settings <- t.settings + 1;
        intent.view.generation)
      else -1
    in
    finish t ~binding_serial ~generation intent.inputs outcome
;;

let kickoff t (ready : ready) =
  if not (current t ready.draft.view
          && match t.preparation with Ready now -> phys_equal ready now | _ -> false)
  then return (Stale stale_preview)
  else if is_pending t
  then return (Rejected pending)
  else (
    let binding_serial = t.binding_serial in
    let inputs = ready.prepared.preview.inputs in
    reset_plan t "Preview already submitted; prepare again for another Kickoff";
    let serial = t.plan_serial in
    t.submission <- Pending inputs;
    touch t;
    let still_current () = current t ready.draft.view && serial = t.plan_serial in
    let%map outcome = send ready.prepared ~still_current in
    finish t ~binding_serial ~generation:ready.draft.view.generation inputs outcome)
;;

(* Public Silver RPC projections. The service above stays useful without a daemon,
   and no alternate launch protocol is needed for fixtures or production. *)
module Wire = struct
  exception Invalid of string
  let invalid message = raise (Invalid message)
  let need ok message = if not ok then invalid message
  let atom s = Sexp.Atom s
  let list xs = Sexp.List xs
  let members fields = List.map fields ~f:(fun (k, v) -> list [ atom k; v ])
  let record fields = list (members fields)
  let inline name fields = list (atom name :: members fields)
  let fields = function Sexp.List xs -> xs | _ -> invalid "Expected Silver list"
  let text = function Sexp.Atom s -> s | _ -> invalid "Expected Silver atom"
  let safe s =
    let buf = Buffer.create 80 in
    let rec loop i =
      if i < String.length s && i < 4096 then (
        let u = Stdlib.String.get_utf_8_uchar s i in
        let n = Stdlib.Uchar.utf_decode_length u in
        let c = Stdlib.Uchar.(utf_decode_uchar u |> to_int) in
        if i + n <= 4096 then (
          if Stdlib.Uchar.utf_decode_is_valid u && c >= 32 && (c < 127 || c > 159)
             && c <> 0x2028 && c <> 0x2029
          then Buffer.add_substring buf s ~pos:i ~len:n
          else Buffer.add_char buf '?';
          loop (i + n)))
    in
    loop 0;
    Buffer.contents buf
  ;;
  let id s =
    need (not (String.is_empty s) && String.equal s (safe s)) "Invalid Silver identity";
    s
  ;;
  let get_opt node key =
    match List.filter_map (fields node) ~f:(function
      | Sexp.List [ Sexp.Atom name; value ] when String.equal name key -> Some value
      | _ -> None) with
    | [] -> None
    | [ value ] -> Some value
    | _ -> invalid ("Duplicate Silver field: " ^ key)
  ;;
  let get node key =
    Option.value_or_thunk (get_opt node key) ~default:(fun () -> invalid ("Missing Silver field: " ^ key))
  ;;
  let opt value = list (Option.to_list value)
  let read_opt = function Sexp.List [] -> None | Sexp.List [ x ] -> Some x | _ -> invalid "Invalid Silver option"
  let opt_field node key = Option.bind (get_opt node key) ~f:read_opt
  let name node key = get node key |> text |> id
  let target ({ chip; variant } : target) = record [ "chip", atom chip; "variant", atom variant ]
  let read_target node = { chip = name node "chip"; variant = name node "variant" }
  let chip_target node = Option.map (opt_field node "chip_target") ~f:read_target
  let assignment (k, v) = k ^ "=" ^ v
  let selection (inputs : inputs) =
    record
      ([ "flow", atom inputs.flow
       ; "profile", atom inputs.profile
       ; "endpoint", atom inputs.endpoint
       ; "assignments", list (List.map inputs.assignments ~f:(fun pair -> atom (assignment pair)))
       ]
       @ Option.value_map inputs.target ~default:[] ~f:(fun value -> [ "chip_target", opt (Some (target value)) ]))
  ;;
  let read_selection node =
    { target = chip_target node
    ; flow = name node "flow"
    ; profile = name node "profile"
    ; endpoint = name node "endpoint"
    ; assignments =
        List.map (fields (get node "assignments")) ~f:(fun atom ->
          match String.lsplit2 (text atom) ~on:'=' with
          | Some (key, value) -> id key, value
          | None -> invalid "Invalid Silver assignment")
    }
  ;;

  type failure =
    | Rpc of string * string
    | Transport of string
    | Invalid_reply of string

  let reason = function Rpc (kind, message) -> kind ^ ": " ^ message | Transport s | Invalid_reply s -> s
  let decode f =
    try Ok (f ()) with
    | Invalid reason -> Error (Invalid_reply reason)
    | _ -> Error (Invalid_reply "Malformed Silver reply")
  ;;
  let rpc_error node = Rpc (name node "kind", safe (text (get node "message")))
  let parse (response : Silver_overview.response) =
    Result.join (decode (fun () ->
      need (String.length response.body <= Silver_http.max_body_bytes) "Silver response exceeds the size limit";
      let node = Sexp.of_string response.body in
      match response.status, node with
      | 200, Sexp.List [ Sexp.Atom "Ok"; data ] -> Ok data
      | 200, Sexp.List [ Sexp.Atom "Error"; data ] -> Error (rpc_error data)
      | (400 | 404 | 413 | 415), _ -> Error (rpc_error node)
      | _ -> Error (Transport (sprintf "Silver HTTP %d" response.status))))
  ;;
  let request project ~path operation =
    Silver_overview.Testing.send_bound project ~path operation
    >>| function
    | Error message -> Error (Transport message)
    | Ok response -> parse response
  ;;

  let decode_query f = Result.map_error (decode f) ~f:reason
  let query rpc operation = rpc operation >>| Result.map_error ~f:reason
  let wait rpc initial f =
    let until = Time_ns.add (Time_ns.now ()) (Time_ns.Span.of_int_sec 30) in
    let rec loop snapshot =
      match decode_query (fun () -> f snapshot) with
      | Error reason | Ok (`Failed reason) -> return (Error reason)
      | Ok (`Ready value) -> return (Ok value)
      | Ok `Pending ->
        if Time_ns.(now () >= until)
        then return (Error "Silver flow query timed out")
        else (
          let%bind () = Clock_ns.after (Time_ns.Span.of_ms 100.) in
          match%bind query rpc (atom "Get") with
          | Error _ as error -> return error
          | Ok snapshot -> loop snapshot)
    in
    match%bind initial with Error _ as error -> return error | Ok snapshot -> loop snapshot
  ;;
  let pending snapshot ~predicate =
    List.filter (fields (get snapshot "operations")) ~f:predicate
  ;;
  let task tasks =
    if List.exists tasks ~f:(fun op -> List.mem [ "pending"; "executing" ] (name op "state") ~equal:String.equal)
    then `Pending
    else
      match List.find tasks ~f:(fun op -> String.equal (name op "state") "failed") with
      | None -> `Settled
      | Some op ->
        `Failed (Option.value_map (opt_field op "error") ~default:"Silver flow query failed" ~f:(fun x -> safe (text x)))
  ;;

  module Json = struct
    let get node key =
      match node with
      | `Assoc fields ->
        (match List.filter_map fields ~f:(fun (name, value) ->
           Option.some_if (String.equal key name) value) with
         | [ value ] -> value
         | _ -> invalid ("Invalid Silver JSON field: " ^ key))
      | _ -> invalid "Expected Silver JSON object"
    ;;
    let str = function `String s -> s | _ -> invalid "Expected Silver JSON string"
    let strings key node = get node key |> function
      | `List items -> List.map items ~f:(fun x -> id (str x))
      | _ -> invalid "Expected Silver JSON string list"
    ;;
    let array node key = match get node key with `List items -> items | _ -> invalid "Expected Silver JSON array"
    let name node key = get node key |> str |> id
    let value = function
      | `String s -> id s
      | `Bool b -> Bool.to_string b
      | _ -> invalid "Unsupported Silver parameter encoding"
    ;;
    let kv node = name node "key", value (get node "value")
    let unique xs =
      need (not (List.contains_dup (List.map xs ~f:fst) ~compare:String.compare))
        "Duplicate Silver parameter key";
      xs
    ;;
    let envelope node contract =
      need (String.equal (name node "contract") contract && Poly.equal (get node "schema_version") (`Int 1))
        "Unsupported Silver flow JSON contract"
    ;;
  end

  let advertised_stages endpoints =
    let known =
      [ "synthesis", "Synthesis", Some Synth
      ; "floorplan", "Floorplan", None
      ; "placement", "Placement", None
      ; "cts", "Clock tree synthesis", None
      ; "routing", "Routing", Some Routing
      ; "timing", "Timing", Some Timing
      ; "signoff", "Signoff", None
      ]
    in
    let row id label alias =
      let endpoint =
        if List.mem endpoints id ~equal:String.equal
        then Available id
        else Unavailable ("Silver does not advertise " ^ label ^ " for this flow")
      in
      { id; label; alias; endpoint }
    in
    List.map known ~f:(fun (id, label, alias) -> row id label alias)
    @ List.filter_map endpoints ~f:(fun id ->
      if List.exists known ~f:(fun (name, _, _) -> String.equal name id)
      then None else Some (row id id None))
  ;;

  let catalog snapshot ~stage_launch =
    let target = chip_target snapshot in
    let default_flow = Option.map (opt_field snapshot "catalog_default") ~f:(fun row -> name row "flow", name row "profile") in
    let flows = List.map (fields (get snapshot "flows")) ~f:(fun row ->
      let flow_id = name row "id" in
      let profiles = List.map (fields (get row "profiles")) ~f:(fun x -> text x |> id) in
      let default_profile = name row "default_profile" in
      let endpoints =
        Option.value_map (get_opt row "fresh_stage_endpoints") ~default:[] ~f:(fun xs ->
          List.map (fields xs) ~f:(fun x -> text x |> id))
      in
      { id = flow_id; label = flow_id; profiles; default_profile; stages = advertised_stages endpoints
      ; kickoff = Unavailable "Silver has not supplied flow input descriptors" })
    in
    { target; default_flow; flows; stage_launch }
  ;;

  let describe_key chip_target flow =
    match chip_target with
    | None -> "describe:" ^ flow
    | Some chip -> "describe-chip:" ^ Sexp.to_string_mach (list [ target chip; atom flow ])
  ;;

  let schema (flow : flow) description =
    let open Json in
    let node = Yojson.Safe.from_string description in
    envelope node "hardcaml-asic.flow-describe";
    let capabilities = get node "capabilities" in
    need (String.equal (name capabilities "stage_selection") "complete-prefix-through-declared-endpoint"
          && Poly.equal (get capabilities "arbitrary_overrides") (`Bool false))
      "Silver did not advertise supported typed flow inputs";
    let entry = get node "entry" in
    let methodology = get entry "methodology" in
    need (String.equal (name methodology "id") flow.id
          && String.equal (name entry "default_profile") flow.default_profile)
      "Silver description is for a different flow";
    let profiles =
      List.map (array entry "profiles") ~f:(fun p ->
        name p "id", List.map (array p "assignments") ~f:kv |> unique)
      |> unique
    in
    need (List.equal String.equal (List.sort (List.map profiles ~f:fst) ~compare:String.compare)
            (List.sort flow.profiles ~compare:String.compare))
      "Silver described a different set of profiles";
    let endpoints =
      strings "endpoints" methodology
      |> List.filter ~f:(fun endpoint ->
        List.exists flow.stages ~f:(fun stage ->
          match stage.endpoint with Available e -> String.equal e endpoint | _ -> false))
    in
    need (not (List.is_empty endpoints)) "Silver has no supported kickoff endpoint for this flow";
    let defaults = List.map (array methodology "defaults") ~f:kv |> unique in
    let descriptors = List.map (array node "parameter_descriptors") ~f:(fun d -> name d "key", d) |> unique in
    let parameters =
      List.map (strings "configurable" methodology) ~f:(fun key ->
        let descriptor =
          match List.Assoc.find descriptors key ~equal:String.equal with
          | Some descriptor -> descriptor
          | None -> invalid ("Missing Silver parameter descriptor: " ^ key)
        in
        let choices = List.map (array descriptor "allowed_values") ~f:value in
        need (not (List.is_empty choices) && List.mem [ "enum"; "boolean" ] (name descriptor "type") ~equal:String.equal)
          "Unsupported Silver parameter descriptor";
        let effective =
          List.map profiles ~f:(fun (_, settings) ->
            Option.first_some (List.Assoc.find settings key ~equal:String.equal)
              (List.Assoc.find defaults key ~equal:String.equal))
        in
        let default =
          match effective with
          | Some value :: rest when List.for_all rest ~f:(Option.equal String.equal (Some value)) -> Some value
          | _ -> None
        in
        { key; label = key; default; choices })
    in
    (* Match Silver's native editor initial choice, not a claimed provider
       default. Restrict it to endpoints present in both public sources. *)
    let default_endpoint =
      if List.mem endpoints "synthesis" ~equal:String.equal then Some "synthesis" else List.hd endpoints
    in
    { flow with label = str (get methodology "label") |> safe
              ; kickoff = Available { endpoints; default_endpoint; parameters } }
  ;;

  let effective_inputs (inputs : inputs) ~identity raw =
    let open Json in
    let node = Yojson.Safe.from_string raw in
    envelope node "hardcaml-asic.methodology-plan";
    need (String.equal (name node "plan_identity") identity) "Silver plan identity mismatch";
    let methodology = get node "methodology" in
    let snapshot = get methodology "snapshot" in
    envelope snapshot "hardcaml-asic.flow-snapshot";
    let selected = get snapshot "selected" in
    need (String.equal (name selected "flow") inputs.flow
          && String.equal (name selected "profile") inputs.profile
          && String.equal (name snapshot "endpoint") inputs.endpoint)
      "Silver plan resolves different flow inputs";
    let sort xs = List.sort xs ~compare:[%compare: string * string] in
    need (List.equal [%equal: string * string] (sort (List.map (array snapshot "request") ~f:kv |> unique))
            (sort inputs.assignments))
      "Silver plan does not contain the captured explicit assignments";
    let assignments =
      List.map (array methodology "effective_parameters") ~f:(fun row ->
        kv (get (get row "winning") "assignment"))
      |> unique
    in
    { inputs with assignments }
  ;;
end

let next_key =
  let counter = ref 0 in
  fun () ->
    incr counter;
    sprintf "cobalt-flow-%d-%s-%d-%08x"
      (Core_unix.getpid () |> Pid.to_int)
      (Time_ns.now () |> Time_ns.to_int63_ns_since_epoch |> Int63.to_string)
      !counter (Random.bits ())
;;

let production project =
  let module P = Silver_overview.Testing in
  let open Wire in
  let binding =
    { endpoint = P.endpoint project; project_root = P.project_root project
    ; instance_id = P.instance_id project; project_id = P.project_id project
    }
  in
  (* A single bounded context per project, distinct from Silver Main/Workspaces.
     Concurrent Cobalt clients may supersede preparation, but never substitute it. *)
  let rpc operation =
    request project ~path:"/api/v1/asic"
      (inline "In_context"
         [ "context", atom "cobalt-companion-v1"
         ; "initial_target", opt None
         ; "operation", operation
         ])
  in
  let get_snapshot () = query rpc (atom "Get") in
  let queue = Throttle.create ~continue_on_error:true ~max_concurrent_jobs:1 in
  let stage_capability () =
    if not (P.supports project "source-bundle-preparation-v1")
    then return (Unavailable "Silver does not advertise source-bundle preparation")
    else (
      let%map result = request project ~path:"/api/v1/preparation" (atom "Get") in
      match result with
      | Error error -> Unavailable (reason error)
      | Ok snapshot ->
        (match decode_query (fun () -> get snapshot "availability") with
         | Ok (Sexp.Atom "Available") -> Available ()
         | Ok (Sexp.List [ Sexp.Atom "Unavailable"; Sexp.Atom "Not_configured" ]) ->
           Unavailable "Silver project has no preparation configuration"
         | Ok (Sexp.List [ Sexp.Atom "Unavailable";
                           Sexp.List [ Sexp.Atom "Invalid_configuration"; Sexp.Atom detail ] ]) ->
           Unavailable ("Invalid Silver preparation configuration: " ^ safe detail)
         | _ -> Unavailable "Silver preparation availability could not be verified"))
  in
  let describe target flow =
    let key = describe_key target flow.id in
    let initial = query rpc (list [ atom "Describe"; atom flow.id ]) in
    wait rpc initial (fun snapshot ->
      need (Option.equal equal_target (chip_target snapshot) target) "Silver launch target changed";
      let tasks = pending snapshot ~predicate:(fun op -> String.equal (name op "key") key) in
      match task tasks with
      | `Pending -> `Pending
      | `Failed reason -> `Failed reason
      | `Settled ->
        (match opt_field snapshot "description_json" with
         | None -> `Failed "Silver flow description unavailable or superseded"
         | Some data -> `Ready (schema flow (text data))))
  in
  let load_catalog () =
    if not (P.supports project "asic")
    then return (Error "Silver does not advertise ASIC operations")
    else (
      match%bind get_snapshot () with
      | Error _ as error -> return error
      | Ok snapshot ->
        (match decode_query (fun () -> name snapshot "configured") with
         | Ok "false" -> return (Error "Silver project has no ASIC flow configuration")
         | Error _ as error -> return error
         | Ok "true" ->
           let%bind stage_launch = stage_capability () in
           let initial = query rpc (atom "Discover") in
           let%bind result =
             wait rpc initial (fun snapshot ->
               match pending snapshot ~predicate:(fun op -> String.equal (name op "key") "discover") |> task with
               | `Failed reason -> `Failed reason
               | `Pending -> `Pending
               | `Settled -> `Ready (Wire.catalog snapshot ~stage_launch))
           in
           (match result with
            | Error _ as error -> return error
            | Ok catalog ->
              let description_deadline = Time_ns.add (Time_ns.now ()) (Time_ns.Span.of_int_sec 30) in
              let%map flows =
                Deferred.List.map catalog.flows ~how:`Sequential ~f:(fun flow ->
                  match stage_launch with
                  | Unavailable reason -> return { flow with kickoff = Unavailable reason }
                  | Available () ->
                    if not (List.exists flow.stages ~f:(fun stage -> Result.is_ok (available stage.endpoint)))
                    then return { flow with kickoff = Unavailable "Silver advertises no fresh endpoint for this flow" }
                    else if Time_ns.(now () >= description_deadline)
                    then return { flow with kickoff = Unavailable "Silver catalog description budget elapsed" }
                    else (
                      match%map describe catalog.target flow with
                      | Ok described -> described
                      | Error reason -> { flow with kickoff = Unavailable reason }))
              in
              Ok { catalog with flows })
         | Ok _ -> return (Error "Invalid Silver ASIC configuration status")))
  in
  let accepted snapshot ~key ~inputs ~intent_id ~expected_plan_identity =
    let workflows = Option.value_map (get_opt snapshot "workflows") ~default:[] ~f:fields in
    match List.filter workflows ~f:(fun row -> String.equal (name row "key") key) with
    | [ workflow ] ->
      let intent = get workflow "intent" in
      need (equal_inputs inputs (read_selection (get intent "selection"))) "Silver acknowledged different inputs";
      Option.iter intent_id ~f:(fun id -> need (String.equal id (name intent "id")) "Silver acknowledged a different intent");
      let expected = Option.map (opt_field intent "expected_plan_identity") ~f:text in
      need (Option.equal String.equal expected expected_plan_identity) "Silver acknowledged a different plan identity";
      need (String.equal (name intent "elaboration_only") "false") "Silver did not acknowledge a physical workflow";
      let run_id = Option.map (opt_field workflow "run") ~f:(fun run ->
        need (String.equal (name run "backend") "asic") "Silver returned a non-ASIC run";
        name run "id")
      in
      Accepted (Workflow { workflow_id = name workflow "id"; run_id })
    | [] when Option.is_some expected_plan_identity ->
      (* Only acknowledge the exact native Run reservation if it returned an
         allocated Run ID; a missing ID is not evidence of no launch. *)
      let launches = Option.value_map (get_opt snapshot "launches") ~default:[] ~f:fields in
      (match List.filter launches ~f:(fun row -> String.equal (name row "key") key) with
       | [ launch ] ->
         let preview = get launch "preview" in
         need (equal_inputs inputs (read_selection (get preview "selection"))
               && Option.equal String.equal expected_plan_identity (Some (name preview "plan_identity")))
           "Silver acknowledged a different run plan";
         (match opt_field launch "run_id" with
          | Some id -> Accepted (Run (text id |> Wire.id))
          | None -> Unconfirmed "Silver reserved submission but has not returned an identity")
       | _ -> Unconfirmed "Silver reply did not confirm this submission")
    | _ -> Unconfirmed "Silver reply did not confirm this submission"
  in
  let submit operation ~key ~inputs ~intent_id ~expected_plan_identity ~still_current =
    if not (still_current ()) then return (Stale stale_preview)
    else match%map rpc operation with
    | Error (Rpc (("Instance_changed" | "Not_found" | "Resync_required"), _) as error) ->
      Stale (reason error)
    | Error (Rpc ("Invalid_request", message) as error)
      when List.exists [ "superseded"; "changed"; "unavailable for this launch context" ]
             ~f:(fun substring -> String.is_substring (String.lowercase message) ~substring) ->
      Stale (reason error)
    | Error (Rpc (("Invalid_request" | "Conflict" | "Unsupported_operation"), _) as error) ->
      Rejected (reason error)
    | Error error -> Unconfirmed (reason error)
    | Ok snapshot ->
      (match decode_query (fun () -> accepted snapshot ~key ~inputs ~intent_id ~expected_plan_identity) with
       | Ok outcome -> outcome
       | Error reason -> Unconfirmed reason)
  in
  let verify_advertised inputs snapshot =
    let catalog = Wire.catalog snapshot ~stage_launch:(Available ()) in
    match check_selection catalog inputs with
    | Error reason -> invalid reason
    | Ok flow ->
      need (List.exists flow.stages ~f:(fun stage ->
        match stage.endpoint with Available e -> String.equal e inputs.endpoint | _ -> false))
        "Silver no longer advertises the captured endpoint";
      flow
  in
  let stage inputs =
    let operation =
      inline "Stage_fresh"
        [ "selection", selection inputs; "elaboration_only", atom "false"
        ; "expected_plan_identity", opt None ]
    in
    let intent snapshot =
      ignore (verify_advertised inputs snapshot : flow);
      match opt_field snapshot "fresh_intent" with
      | None -> invalid "Silver did not return a staged fresh intent"
      | Some intent ->
        need (equal_inputs inputs (read_selection (get intent "selection"))
              && String.equal (name intent "elaboration_only") "false"
              && Option.is_none (opt_field intent "expected_plan_identity"))
          "Silver staged different inputs";
        name intent "id"
    in
    match%bind query rpc operation with
    | Error _ as error -> return error
    | Ok snapshot ->
      (match decode_query (fun () -> intent snapshot) with
       | Error _ as error -> return error
       | Ok identity ->
         match%map get_snapshot () with
         | Error _ as error -> error
         | Ok snapshot ->
           decode_query (fun () ->
             need (String.equal identity (intent snapshot)) "Silver fresh intent was superseded";
             let key = next_key () in
              let operation = inline "Launch_fresh" [ "key", atom key; "intent_id", atom identity ] in
             { preview = { identity; inputs }
             ; submit = submit operation ~key ~inputs ~intent_id:(Some identity) ~expected_plan_identity:None
             }))
  in
  let plan inputs =
    let initial = query rpc (list [ atom "Plan"; selection inputs ]) in
    let%map result =
      wait rpc initial (fun snapshot ->
        ignore (verify_advertised inputs snapshot : flow);
        match opt_field snapshot "preview" with
        | Some exact_preview when equal_inputs inputs (read_selection (get exact_preview "selection")) ->
          let identity = name exact_preview "plan_identity" in
          let raw = get exact_preview "plan_json" |> text in
          let resolved = effective_inputs inputs ~identity raw in
          `Ready (exact_preview, identity, resolved)
        | _ ->
          (match pending snapshot ~predicate:(fun op -> String.equal (name op "kind") "plan") |> task with
           | `Pending -> `Pending
           | `Failed reason -> `Failed reason
           | `Settled -> `Failed "Silver flow plan unavailable or superseded"))
    in
    Result.bind result ~f:(fun (exact_preview, identity, resolved) ->
      let key = next_key () in
       let operation = inline "Run" [ "key", atom key; "preview", exact_preview ] in
      if String.length (Sexp.to_string_mach operation) > (1024 * 1024) - 16384
      then Error "Silver exact plan exceeds its submission size limit"
      else
         let send ~still_current =
           match%bind get_snapshot () with
           | Error reason -> return (Rejected ("Could not revalidate preview: " ^ reason))
           | Ok snapshot ->
             (match decode_query (fun () ->
                ignore (verify_advertised inputs snapshot : flow);
                need
                  (Option.exists (opt_field snapshot "preview") ~f:(Sexp.equal exact_preview))
                  "Silver reviewed preview was superseded; prepare again") with
              | Error reason -> return (Stale reason)
              | Ok () ->
                submit operation ~key ~inputs ~intent_id:None
                  ~expected_plan_identity:(Some identity) ~still_current)
         in
         Ok { preview = { identity; inputs = resolved }; submit = send })
  in
  let prepare request =
    Throttle.enqueue queue (fun () ->
      let inputs = match request with Stage inputs | Kickoff inputs -> inputs in
      match%bind get_snapshot () with
      | Error _ as error -> return error
      | Ok snapshot ->
        (match decode_query (fun () -> verify_advertised inputs snapshot) with
         | Error _ as error -> return error
         | Ok flow ->
           (match request with
            | Kickoff _ -> plan inputs
            | Stage _ when List.is_empty inputs.assignments -> stage inputs
            | Stage _ ->
              (* Stage_fresh only validates assignment encoding. Recheck the
                 public descriptors before accepting explicit saved overrides. *)
              (match%bind describe inputs.target flow with
               | Error _ as error -> return error
               | Ok described ->
                 (match Result.bind (available described.kickoff) ~f:(fun schema ->
                    check_assignments ~parameters:(Some schema.parameters) inputs.assignments) with
                  | Error _ as error -> return error
                  | Ok () -> stage inputs)))))
  in
  { binding; catalog = (fun () -> Throttle.enqueue queue load_catalog); prepare }
;;
