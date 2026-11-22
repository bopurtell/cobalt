open! Core
open! Async

type binding =
  { endpoint : string
  ; project_root : string
  ; run : string option
  }

type attempt =
  { id : string
  ; suite : string
  ; lifecycle : string
  ; outcome : string option
  }

type snapshot =
  { binding : binding
  ; instance_id : string
  ; project_id : string
  ; attempts : attempt list
  ; truncated : bool
  }

type availability =
  | Unavailable of string
  | Fresh of snapshot
  | Stale of snapshot * string

type request =
  { meth : [ `Get | `Post ]
  ; path : string
  ; headers : (string * string) list
  ; body : string
  }

type response = { status : int; body : string }

type peer =
  endpoint:string ->
  timeout:Time_ns.Span.t ->
  stop:unit Deferred.t ->
  request ->
  (response, string) result Deferred.t

let http_peer ~endpoint ~timeout ~stop { meth; path; headers; body } =
  Silver_http.request ~endpoint ~timeout ~stop ~meth ~path ~headers ~body
  >>| Result.map ~f:(fun (status, body) -> { status; body })
;;

let max_identity_bytes = 4096
let max_status_rows = 25
let max_label_bytes = 256

(* Use valid, single-line display text. Silver identifiers used in requests are never
   rewritten; identities containing control or invalid UTF-8 bytes are rejected. *)
let sanitize ~max text =
  let n = String.length text in
  let buf = Buffer.create (Int.min n max) in
  let rec loop i =
    if i < n && i < max
    then (
      let u = Stdlib.String.get_utf_8_uchar text i in
      let len = Stdlib.Uchar.utf_decode_length u in
      if i + len <= max
      then (
        let code = Stdlib.Uchar.utf_decode_uchar u |> Stdlib.Uchar.to_int in
        if not (Stdlib.Uchar.utf_decode_is_valid u)
           || code < 32 || (code >= 127 && code <= 159)
           || code = 0x2028 || code = 0x2029
        then Buffer.add_char buf '?'
        else Buffer.add_substring buf text ~pos:i ~len;
        loop (i + len)))
  in
  loop 0;
  Buffer.contents buf
;;

let valid_identity text =
  (not (String.is_empty text))
  && String.length text <= max_identity_bytes
  && String.equal text (sanitize ~max:max_identity_bytes text)
;;

module Wire = struct
  let atom text = Sexp.Atom text
  let list values = Sexp.List values
  let record fields = list (List.map fields ~f:(fun (key, value) -> list [ atom key; value ]))

  exception Invalid of string

  let invalid text = raise (Invalid text)

  let values = function
    | Sexp.List values -> values
    | Sexp.Atom _ -> invalid "Expected a Silver list"
  ;;

  let text = function
    | Sexp.Atom text -> text
    | Sexp.List _ -> invalid "Expected a Silver atom"
  ;;

  let identity sexp =
    let text = text sexp in
    if not (valid_identity text) then invalid "Invalid Silver identity";
    text
  ;;

  let find field sexp =
    List.fold (values sexp) ~init:None ~f:(fun found -> function
      | Sexp.List [ Sexp.Atom key; value ] when String.equal key field ->
        if Option.is_some found then invalid ("Duplicate Silver field: " ^ field);
        Some value
      | _ -> found)
  ;;

  let field sexp key =
    match find key sexp with
    | Some value -> value
    | None -> invalid ("Missing Silver field: " ^ key)
  ;;

  let option = function
    | Sexp.List [] -> None
    | Sexp.List [ value ] -> Some value
    | _ -> invalid "Invalid Silver option"
  ;;

  let decode body f =
    if String.length body > Silver_http.max_body_bytes
    then Error "Silver HTTP body exceeds the size limit"
    else (
      try Ok (f (Sexp.of_string body)) with
      | Invalid text -> Error text
      | _ -> Error "Malformed Silver S-expression")
  ;;

  let error_fields sexp = field sexp "kind" |> text, field sexp "message" |> text

  let error_message (kind, message) = sanitize ~max:max_label_bytes (kind ^ ": " ^ message)

  let rpc_error sexp = invalid (error_fields sexp |> error_message)
  ;;

  let result f = function
    | Sexp.List [ Sexp.Atom "Ok"; payload ] -> f payload
    | Sexp.List [ Sexp.Atom "Error"; payload ] -> rpc_error payload
    | _ -> invalid "Invalid Silver RPC result"
  ;;

  let hello sexp =
    if not (List.exists (field sexp "protocol_versions" |> values) ~f:(Sexp.equal (atom "1")))
    then invalid "Silver daemon does not support protocol v1";
    if not (List.exists (field sexp "capabilities" |> values) ~f:(Sexp.equal (atom "simulation")))
    then invalid "Silver daemon does not support simulation observation";
    field sexp "instance_id" |> identity
  ;;

  let opened ~project_root = result (fun payload ->
    let project = field payload "project" in
    let root = field (field project "root") "path" |> identity in
    if not (String.equal root project_root)
    then invalid "Silver opened a different project root (use its canonical absolute path)";
    field project "id" |> identity)
  ;;

  let lifecycle sexp =
    match text sexp with
    | ("Queued" | "Running" | "Finished" | "Cancelled" | "Interrupted") as value -> value
    | _ -> invalid "Unknown Silver simulation lifecycle"
  ;;

  let outcome sexp =
    match text sexp with
    | "Unknown" -> None
    | ("Passed" | "Failed" | "Incomplete") as value -> Some value
    | _ -> invalid "Unknown Silver simulation outcome"
  ;;

  let attempt sexp ~selection =
    { id = field sexp "id" |> identity
    ; suite = field selection "suite" |> text |> sanitize ~max:max_label_bytes
    ; lifecycle = field sexp "lifecycle" |> lifecycle
    ; outcome = field sexp "outcome" |> outcome
    }
  ;;

  let snapshot ~binding ~instance_id ~project_id = result (fun payload ->
    let attempts, truncated =
      match binding.run with
      | None ->
        let rows = field payload "attempts" |> values in
        let truncated =
          List.length rows > max_status_rows
          || Option.exists (find "next_before" payload) ~f:(fun page -> Option.is_some (option page))
        in
        List.map (List.take rows max_status_rows) ~f:(fun row -> attempt row ~selection:row), truncated
      | Some id ->
        let detail =
          match field payload "detail" |> option with
          | Some detail -> detail
          | None -> invalid "Silver did not return the requested attempt"
        in
        let root = field detail "project_root" |> identity in
        if not (String.equal root binding.project_root)
        then invalid "Silver attempt belongs to a different project";
        let row = attempt detail ~selection:(field (field detail "captured") "selection") in
        if not (String.equal row.id id) then invalid "Silver returned a different attempt";
        [ row ], false
    in
    { binding; instance_id; project_id; attempts; truncated })
  ;;

  let hello_request = { meth = `Get; path = "/api/hello"; headers = []; body = "" }

  let post ~path fields =
    { meth = `Post
    ; path
    ; headers = [ "Content-Type", "application/sexp"; "X-Workbench-Protocol", "1" ]
    ; body = record fields |> Sexp.to_string_mach
    }
  ;;

  let open_project_request ~instance_id ~project_root =
    post ~path:"/api/v1/open-project"
      [ "instance_id", atom instance_id; "root", atom project_root; "environment", atom "Inherit_daemon" ]
  ;;

  let simulation_request ~instance_id ~project_id operation =
    post ~path:"/api/v1/simulation"
      [ "instance_id", atom instance_id; "project", atom project_id; "operation", operation ]
  ;;

  let status_request ~instance_id ~project_id ~run =
    let operation =
      match run with
      | None -> atom "Get"
      | Some run -> list [ atom "Observe"; atom run ]
    in
    simulation_request ~instance_id ~project_id operation
  ;;
end

type session =
  { binding : binding
  (* Identity of this binding's lifetime, not just equality of its values. *)
  ; stop : unit Ivar.t
  ; mutable request_stop : unit Ivar.t option
  }

type t =
  { peer : peer
  ; timeout : Time_ns.Span.t
  ; poll_interval : Time_ns.Span.t
  ; retry_initial : Time_ns.Span.t
  ; retry_max : Time_ns.Span.t
  ; mutable disposed : bool
  ; mutable session : session option
  ; mutable availability : availability
  ; mutable revision : int
  ; mutable changed : unit Ivar.t
  }

let create
  ?(peer = http_peer)
  ?(timeout = Time_ns.Span.of_int_sec 5)
  ?(poll_interval = Time_ns.Span.of_int_sec 1)
  ?(retry_initial = Time_ns.Span.of_int_ms 250)
  ?(retry_max = Time_ns.Span.of_int_sec 5)
  ()
  =
  List.iter [ timeout; poll_interval; retry_initial; retry_max ] ~f:(fun span ->
    if Time_ns.Span.(span <= zero) then invalid_arg "Silver time intervals must be positive");
  if Time_ns.Span.(retry_max < retry_initial)
  then invalid_arg "Silver retry_max must not be smaller than retry_initial";
  { peer; timeout; poll_interval; retry_initial; retry_max; disposed = false; session = None
  ; availability = Unavailable "No Silver binding"; revision = 0; changed = Ivar.create ()
  }
;;

let latest t = t.availability
let revision t = t.revision
let await_change t ~after = if t.revision <> after then Deferred.unit else Ivar.read t.changed

let publish ?(force = false) t value =
  if force || not (Poly.equal t.availability value)
  then (
    t.availability <- value;
    t.revision <- t.revision + 1;
    Ivar.fill_if_empty t.changed ();
    t.changed <- Ivar.create ())
;;

let active session = not (Ivar.is_full session.stop)

let previous t =
  match t.availability with
  | Unavailable _ -> None
  | Fresh snapshot | Stale (snapshot, _) -> Some snapshot
;;

let read t (session : session) request decode =
  if not (active session)
  then return (Error "Silver binding closed")
  else (
    let stop = Ivar.create () in
    session.request_stop <- Some stop;
    let peer =
      Monitor.try_with ~rest:(`Call ignore) (fun () ->
        t.peer ~endpoint:session.binding.endpoint ~timeout:t.timeout ~stop:(Ivar.read stop) request)
    in
    let%map result =
      Clock_ns.with_timeout t.timeout
        (Deferred.choose
           [ Deferred.choice (Ivar.read session.stop) (fun () -> Error "Silver binding closed")
           ; Deferred.choice peer (function Ok response -> response | Error _ -> Error "Silver transport failed")
           ])
    in
    (match result with
     | `Timeout -> Ivar.fill_if_empty stop ()
     | `Result _ -> ());
    session.request_stop <- None;
    if not (active session)
    then Error "Silver binding closed"
    else
      let decoded =
        match result with
        | `Timeout -> Error "Silver request timed out"
        | `Result (Error reason) -> Error reason
        | `Result (Ok { status = 200; body }) -> Wire.decode body decode
        | `Result (Ok { status; body }) ->
          let reason = Wire.decode body Wire.rpc_error in
          let reason = match reason with Error text -> text | Ok _ -> assert false in
          Error (Printf.sprintf "Silver HTTP %d: %s" status reason)
      in
      Result.map_error decoded ~f:(sanitize ~max:max_label_bytes))
;;

let connect t (session : session) =
  let project_root = session.binding.project_root in
  match%bind read t session Wire.hello_request Wire.hello with
  | Error reason -> return (Error reason)
  | Ok instance_id ->
    if active session && Option.exists (previous t) ~f:(fun old ->
      not (String.equal old.instance_id instance_id))
    then publish t (Unavailable "Silver daemon instance changed; reopening project");
    let%map result =
      read t session (Wire.open_project_request ~instance_id ~project_root) (Wire.opened ~project_root)
    in
    Result.map result ~f:(fun project_id ->
      if active session && Option.exists (previous t) ~f:(fun old ->
        not (String.equal old.project_id project_id))
      then publish t (Unavailable "Silver project session changed; reading status");
      instance_id, project_id)
;;

let rec loop t (session : session) ~connection ~backoff =
  if not (active session)
  then Deferred.unit
  else (
    let binding = session.binding in
    let%bind connection =
      match connection with Some ids -> return (Ok ids) | None -> connect t session
    in
    let%bind result =
      match connection with
      | Error reason -> return (Error reason)
      | Ok (instance_id, project_id) ->
        read t session (Wire.status_request ~instance_id ~project_id ~run:binding.run)
          (Wire.snapshot ~binding ~instance_id ~project_id)
    in
    if not (active session)
    then Deferred.unit
    else (
      let wait, connection, backoff =
        match result with
        | Ok snapshot ->
          publish t (Fresh snapshot);
          t.poll_interval, Result.ok connection, t.retry_initial
        | Error reason ->
          publish t
            (match previous t with
             | None -> Unavailable reason
             | Some latest -> Stale (latest, reason));
          let next =
            if Time_ns.Span.(backoff >= t.retry_max - backoff)
            then t.retry_max
            else Time_ns.Span.(backoff + backoff)
          in
          backoff, None, next
      in
      let%bind () =
        Deferred.any_unit [ Ivar.read session.stop; Clock_ns.after wait ]
      in
      loop t session ~connection ~backoff))
;;

let release t =
  Option.iter t.session ~f:(fun session ->
    Ivar.fill_if_empty session.stop ();
    Option.iter session.request_stop ~f:(fun stop -> Ivar.fill_if_empty stop ()));
  t.session <- None
;;

let rebind t binding =
  if not t.disposed
  then (
    release t;
    if not (valid_identity binding.endpoint)
    then publish ~force:true t (Unavailable "Invalid explicit Silver endpoint")
    else if not (valid_identity binding.project_root) || Filename.is_relative binding.project_root
    then publish ~force:true t (Unavailable "Silver project root must be an absolute canonical path")
    else if Option.exists binding.run ~f:(fun run -> not (valid_identity run))
    then publish ~force:true t (Unavailable "Invalid Silver attempt ID")
    else (
      let session = { binding; stop = Ivar.create (); request_stop = None } in
      t.session <- Some session;
      publish ~force:true t (Unavailable "Connecting to Silver");
      upon Deferred.unit (fun () ->
        don't_wait_for (loop t session ~connection:None ~backoff:t.retry_initial))))
;;

let unbind t =
  if not t.disposed
  then (
    release t;
    publish t (Unavailable "No Silver binding"))
;;

let shutdown t =
  if not t.disposed
  then (
    t.disposed <- true;
    release t;
    publish t (Unavailable "Silver observation stopped"))
;;

module Testing = struct
  type connection =
    { peer : peer
    ; endpoint : string
    ; project_root : string
    ; timeout : Time_ns.Span.t
    ; closed : unit Ivar.t
    }

  type project =
    { connection : connection
    ; instance_id : string
    ; project_id : string
    }

  let close project = Ivar.fill_if_empty project.connection.closed ()
  let project_root project = project.connection.project_root

  let send ?deadline connection request =
    let timeout =
      match deadline with
      | None -> connection.timeout
      | Some deadline ->
        Time_ns.Span.min connection.timeout (Time_ns.diff deadline (Time_ns.now ()))
    in
    if Ivar.is_full connection.closed
    then return (Error "Silver project connection closed")
    else if Time_ns.Span.(timeout <= zero)
    then return (Error "Silver catalog discovery timed out")
    else (
      let stop = Ivar.create () in
      let peer =
        Monitor.try_with ~rest:(`Call ignore) (fun () ->
          connection.peer ~endpoint:connection.endpoint ~timeout ~stop:(Ivar.read stop) request)
      in
      let%map response =
        Clock_ns.with_timeout timeout
          (Deferred.choose
             [ Deferred.choice (Ivar.read connection.closed)
                 (fun () -> Error "Silver project connection closed")
             ; Deferred.choice peer (function
                 | Ok (Ok response) -> Ok response
                 | Ok (Error _) | Error _ -> Error "Silver transport failed")
             ])
      in
      Ivar.fill_if_empty stop ();
      match response with
      | `Timeout -> Error "Silver request timed out"
      | `Result result -> result)
  ;;

  let read ?deadline connection request decode =
    match%map send ?deadline connection request with
    | Error _ as error -> error
    | Ok { status = 200; body } -> Wire.decode body decode
    | Ok { status; body } ->
      let reason =
        match Wire.decode body Wire.error_fields with
        | Ok fields -> ": " ^ Wire.error_message fields
        | Error _ -> ""
      in
      Error (sprintf "Silver HTTP %d%s" status reason)
  ;;

  let connect ?(peer = http_peer) ?(timeout = Time_ns.Span.of_int_sec 5)
        ?expected_instance_id ~endpoint ~project_root () =
    if not (valid_identity endpoint)
    then return (Error "Invalid explicit Silver endpoint")
    else if not (valid_identity project_root) || Filename.is_relative project_root
    then return (Error "Silver project root must be an absolute canonical path")
    else if Time_ns.Span.(timeout <= zero)
    then return (Error "Silver request timeout must be positive")
    else (
      let connection = { peer; endpoint; project_root; timeout; closed = Ivar.create () } in
      match%bind read connection Wire.hello_request Wire.hello with
      | Error _ as error -> return error
      | Ok instance_id
        when Option.exists expected_instance_id ~f:(fun expected ->
          not (String.equal instance_id expected)) ->
        return (Error "Silver advertisement names a different daemon instance")
      | Ok instance_id ->
        let%map project =
          read connection (Wire.open_project_request ~instance_id ~project_root)
            (Wire.opened ~project_root)
        in
        Result.map project ~f:(fun project_id -> { connection; instance_id; project_id }))
  ;;

  type parameter =
    { key : string
    ; label : string
    ; default : string
    ; choices : string list
    }

  type case = { id : string; label : string }

  type suite =
    { id : string
    ; label : string
    ; cases : case list
    ; parameters : parameter list
    ; default_seed : string
    }

  type catalog =
    { project : project
    ; digest : string
    ; suites : suite list
    ; mutable stale : string option
    }

  let digest catalog = catalog.digest
  let suites catalog = catalog.suites

  let check condition message = if not condition then Wire.invalid message

  let provider_text atom =
    let value = Wire.text atom in
    check (String.length value <= 4096 && not (String.contains value '\000'))
      "Invalid Silver Testing value";
    value
  ;;

  let label atom = provider_text atom |> sanitize ~max:max_label_bytes

  let provider_key atom =
    let value = Wire.text atom in
    let alphanumeric = function
      | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' -> true
      | _ -> false
    in
    check
      (String.length value <= 128
       && not (String.is_empty value)
       && alphanumeric value.[0]
       && String.for_all value ~f:(fun c ->
         alphanumeric c || Char.equal c '.' || Char.equal c '_' || Char.equal c '-'))
      "Invalid Silver Testing key";
    value
  ;;

  let parse_list ~max atom ~f =
    let values = Wire.values atom in
    check (List.length values <= max) "Silver Testing list exceeds its protocol limit";
    List.map values ~f
  ;;

  let unique values ~key =
    check
      (not (List.contains_dup (List.map values ~f:key) ~compare:String.compare))
      "Duplicate Silver Testing key";
    values
  ;;

  let seed_valid value =
    let length = String.length value in
    length > 0 && length <= 20 && String.for_all value ~f:Char.is_digit
    && (length = 1 || not (Char.equal value.[0] '0'))
    && (length < 20 || String.compare value "18446744073709551615" <= 0)
  ;;

  let parameter sexp =
    let field = Wire.field sexp in
    let default = field "default" |> provider_text in
    let choices = parse_list ~max:64 (field "choices") ~f:provider_text in
    check (List.is_empty choices || List.mem choices default ~equal:String.equal)
      "Silver Testing default is not a declared choice";
    { key = field "key" |> provider_key; label = field "label" |> label; default; choices }
  ;;

  let case sexp : case =
    { id = Wire.field sexp "id" |> provider_key; label = Wire.field sexp "label" |> label }
  ;;

  let suite sexp =
    let field = Wire.field sexp in
    let cases =
      parse_list ~max:1024 (field "cases") ~f:case |> unique ~key:(fun (case : case) -> case.id)
    in
    let parameters = parse_list ~max:32 (field "parameters") ~f:parameter |> unique ~key:(fun p -> p.key) in
    let default_seed = field "default_seed" |> Wire.text in
    check (not (List.is_empty cases) && seed_valid default_seed) "Invalid Silver Testing suite";
    { id = field "id" |> provider_key; label = field "label" |> label; cases; parameters; default_seed }
  ;;

  let catalog_state project = Wire.result (fun sexp ->
    let field = Wire.field sexp in
    let configured =
      match field "configured" |> Wire.text with
      | "true" -> true
      | "false" -> false
      | _ -> Wire.invalid "Invalid Silver Testing configured state"
    in
    match configured, field "discovery_digest" |> Wire.option with
    | false, _ -> `Unavailable "Silver Testing provider is not configured"
    | true, Some digest ->
      let digest = Wire.identity digest in
      let discovery =
        Option.value_or_thunk (field "discovery" |> Wire.option)
          ~default:(fun () -> Wire.invalid "Silver Testing digest has no catalog")
      in
      check (String.equal (Wire.field discovery "protocol_version" |> Wire.text) "1")
        "Unsupported Silver Testing provider version";
      let suites =
        parse_list ~max:64 (Wire.field discovery "suites") ~f:suite |> unique ~key:(fun suite -> suite.id)
      in
      check (List.sum (module Int) suites ~f:(fun suite -> List.length suite.cases) <= 1024)
        "Too many Silver Testing cases";
      `Ready { project; digest; suites; stale = None }
    | true, None ->
      (match field "discovery_job" |> Wire.option, field "discovery_error" |> Wire.option with
       | Some _, _ -> `Pending
       | None, Some reason -> `Missing (Wire.text reason |> sanitize ~max:max_label_bytes)
       | None, None -> `Missing "Silver has no current Testing catalog"))
  ;;

  let rpc project operation =
    Wire.simulation_request ~instance_id:project.instance_id ~project_id:project.project_id operation
  ;;

  let discover ?(discovery_timeout = Time_ns.Span.of_int_sec 30) project =
    let deadline = Time_ns.add (Time_ns.now ()) discovery_timeout in
    let read_catalog operation =
      read ~deadline project.connection (rpc project (Wire.atom operation)) (catalog_state project)
    in
    let rec get operation ~may_start =
      match%bind read_catalog operation with
      | Error _ as error -> return error
      | Ok (`Ready catalog) -> return (Ok catalog)
      | Ok (`Unavailable reason) -> return (Error reason)
      | Ok (`Missing _) when may_start -> get "Discover" ~may_start:false
      | Ok (`Missing reason) -> return (Error reason)
      | Ok `Pending ->
        let pause = Time_ns.Span.min (Time_ns.Span.of_int_ms 100)
            (Time_ns.diff deadline (Time_ns.now ()))
        in
        if Time_ns.Span.(pause <= zero)
        then return (Error "Silver catalog discovery timed out")
        else (
          let%bind () = Deferred.any_unit [ Ivar.read project.connection.closed; Clock_ns.after pause ] in
          get "Get" ~may_start:false)
    in
    get "Get" ~may_start:true
  ;;

  type acceptance = { attempt_id : string; job_id : string }

  type launch_result =
    | Accepted of acceptance
    | Stale_catalog of string
    | Rejected of string
    | Uncertain of string

  let submission_index = ref 0

  let submission_key () =
    incr submission_index;
    sprintf "cobalt-test-%d-%s-%d-%08x"
      (Core_unix.getpid () |> Pid.to_int)
      (Time_ns.now () |> Time_ns.to_int63_ns_since_epoch |> Int63.to_string)
      !submission_index (Random.bits ())
  ;;

  let sorted_cases = List.sort ~compare:String.compare
  let sorted_parameters = List.sort ~compare:(fun (a, _) (b, _) -> String.compare a b)

  let selection catalog ~suite ~cases ~seed ~parameters =
    match List.find catalog.suites ~f:(fun row -> String.equal row.id suite) with
    | None -> Error "Unknown Silver Testing suite"
    | Some row ->
      if List.is_empty cases
         || List.length cases > List.length row.cases
         || List.contains_dup cases ~compare:String.compare
         || not (List.for_all cases ~f:(fun id -> List.exists row.cases ~f:(fun (case : case) -> String.equal case.id id)))
      then Error "Choose explicit, distinct cases from the Silver Testing suite"
      else if not (seed_valid seed)
      then Error "Silver Testing seed must be a canonical unsigned 64-bit decimal"
      else if List.length parameters <> List.length row.parameters
              || List.contains_dup (List.map parameters ~f:fst) ~compare:String.compare
              || not (List.for_all parameters ~f:(fun (key, value) ->
                String.length value <= 4096 && not (String.contains value '\000')
                && List.exists row.parameters ~f:(fun parameter ->
                  String.equal parameter.key key
                  && (List.is_empty parameter.choices
                      || List.mem parameter.choices value ~equal:String.equal))))
      then Error "Supply exactly the declared Silver Testing parameters with valid values"
      else
        let open Wire in
        Ok (record
          [ "suite", atom suite
          ; "cases", list (List.map cases ~f:atom)
          ; "seed", atom seed
          ; "parameters", list (List.map parameters ~f:(fun (k, v) -> list [ atom k; atom v ]))
          ; "asic_inputs", list []
          ])
  ;;

  let acceptance catalog ~suite ~cases ~seed ~parameters payload =
    let open Wire in
    let detail =
      Option.value_or_thunk (field payload "detail" |> option)
        ~default:(fun () -> invalid "Silver launch reply did not identify an attempt")
    in
    check (String.equal (field detail "project_root" |> identity) (project_root catalog.project))
      "Silver launch acknowledgement belongs to a different project";
    let captured = field detail "captured" in
    let returned = field captured "selection" in
    let actual_cases = parse_list ~max:1024 (field returned "cases") ~f:provider_key in
    let actual_parameters =
      parse_list ~max:32 (field returned "parameters") ~f:(function
        | Sexp.List [ key; value ] -> provider_key key, provider_text value
        | _ -> invalid "Malformed parameter in Silver launch acknowledgement")
    in
    check
      (String.equal (field captured "discovery_digest" |> identity) catalog.digest
       && String.equal (field returned "suite" |> text) suite
       && String.equal (field returned "seed" |> text) seed
       && List.equal String.equal (sorted_cases cases) (sorted_cases actual_cases)
       && List.equal (Tuple2.equal ~eq1:String.equal ~eq2:String.equal)
            (sorted_parameters parameters) (sorted_parameters actual_parameters)
       && List.is_empty (field returned "asic_inputs" |> values))
      "Silver launch acknowledgement does not match the captured inputs";
    { attempt_id = field detail "id" |> identity; job_id = field detail "job" |> identity }
  ;;

  let rejected ((kind, message) as fields) =
    let reason = Wire.error_message fields in
    match kind, message with
    | "Conflict", ("Stale simulation discovery digest"
                  | "Current successful simulation discovery is required"
                  | "Discover simulation suites first"
                  | "Simulation configuration/discovery changed before reservation") ->
      Stale_catalog reason
    | ("Invalid_request" | "Unsupported_operation" | "Not_found" | "Conflict" | "Instance_changed"), _ ->
      Rejected reason
    (* Silver can return Internal_failure after persisting a reservation. *)
    | _ -> Uncertain reason
  ;;

  let launch catalog ~suite ~cases ~seed ~parameters =
    if Ivar.is_full catalog.project.connection.closed
    then return (Rejected "Silver project connection closed")
    else
      match catalog.stale, selection catalog ~suite ~cases ~seed ~parameters with
      | Some reason, _ -> return (Stale_catalog reason)
      | None, Error reason -> return (Rejected reason)
      | None, Ok selection ->
        let request =
          let open Wire in
          rpc catalog.project
            (list [ atom "Launch"
                  ; list [ atom "submission_key"; atom (submission_key ()) ]
                  ; list [ atom "discovery_digest"; atom catalog.digest ]
                  ; list [ atom "selection"; selection ]
                  ])
        in
        if String.length request.body > 1024 * 1024
        then return (Rejected "Silver Testing request exceeds the protocol size limit")
        else (
          let%map response = send catalog.project.connection request in
          let result =
            match response with
            | Error reason -> Uncertain reason
            | Ok { status; body } ->
              let decoded =
                Wire.decode body (fun sexp ->
                  match status, sexp with
                  | 200, Sexp.List [ Sexp.Atom "Ok"; payload ] ->
                    Accepted (acceptance catalog ~suite ~cases ~seed ~parameters payload)
                  | 200, Sexp.List [ Sexp.Atom "Error"; payload ] ->
                    rejected (Wire.error_fields payload)
                  | (400 | 404 | 413), _ ->
                    (match Wire.error_fields sexp with
                     | (("Invalid_request" | "Not_found"), _) as error -> rejected error
                     | _ -> Uncertain (sprintf "Unexpected Silver HTTP %d reply" status))
                  | _ -> Uncertain (sprintf "Unexpected Silver launch reply (HTTP %d)" status))
              in
              (match decoded with Ok result -> result | Error reason -> Uncertain reason)
          in
          (match result with Stale_catalog reason -> catalog.stale <- Some reason | _ -> ());
          result)
  ;;
end
