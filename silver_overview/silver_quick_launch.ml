open! Core

type project =
  { endpoint : string
  ; project_root : string
  }

type case =
  { id : string
  ; label : string
  }
[@@deriving equal]

type parameter =
  { key : string
  ; label : string
  ; default : string
  ; choices : string list
  }
[@@deriving equal]

type suite =
  { id : string
  ; label : string
  ; cases : case list
  ; parameters : parameter list
  ; default_seed : string
  }
[@@deriving equal]

type catalog =
  { discovery_digest : string
  ; suites : suite list
  }
[@@deriving equal]

type target =
  | Suite of string
  | Variant of { suite_id : string; case_id : string }

type field_id =
  | Seed
  | Parameter of string
[@@deriving equal]

type field =
  { id : field_id
  ; label : string
  ; value : string
  ; default : string
  ; choices : string list
  }

type saved_values = (field_id * string) list

type project_state =
  { catalog : catalog option
  ; error : string option
  ; generation : int
  ; needs_selection : bool
  ; confirmed : (target, Comparator.Poly.comparator_witness) Set.t
  ; overrides : (target, saved_values, Comparator.Poly.comparator_witness) Map.t
  ; configured_default : target option
  ; last_launched : target option
  }

type t = (project, project_state, Comparator.Poly.comparator_witness) Map.t

type catalog_view =
  { project : project
  ; catalog : catalog
  ; generation : int
  }

type selected =
  { view : catalog_view
  ; target : target
  }

type edit =
  { selected : selected
  ; fields : field list
  }

let empty = Map.Poly.empty

let empty_project =
  { catalog = None
  ; error = Some "Discover a Silver test catalog first"
  ; generation = 0
  ; needs_selection = false
  ; confirmed = Set.Poly.empty
  ; overrides = Map.Poly.empty
  ; configured_default = None
  ; last_launched = None
  }
;;

let state t project = Map.find t project |> Option.value ~default:empty_project
let update t project ~f = Map.set t ~key:project ~data:(f (state t project))

let fence (p : project_state) =
  { p with
    generation = p.generation + 1
  ; needs_selection = Option.is_some p.catalog
  ; confirmed = Set.Poly.empty
  }
;;

let set_catalog t ~project catalog =
  update t project ~f:(fun p ->
    let p =
      if Option.exists p.catalog ~f:(fun previous ->
        Option.is_some p.error || not (equal_catalog previous catalog))
      then fence p
      else p
    in
    { p with catalog = Some catalog; error = None })
;;

let invalidate_catalog t ~project ~reason =
  update t project ~f:(fun p -> { (fence p) with error = Some reason })
;;

let catalog_view t ~project =
  let ({ catalog; generation; _ } : project_state) = state t project in
  Option.map catalog ~f:(fun catalog -> { project; catalog; generation })
;;

let catalog_contents view = view.catalog
let catalog_error t ~project = (state t project).error

let stale = "Silver test catalog changed; select the target again"

let check_view t view =
  let p = state t view.project in
  match p.error, p.catalog with
  | Some reason, _ -> Error reason
  | None, Some current
    when p.generation = view.generation
         && (phys_equal current view.catalog || equal_catalog current view.catalog) ->
    Ok p
  | _ -> Error stale
;;

let find_target (catalog : catalog) target =
  let suite_id =
    match target with
    | Suite id -> id
    | Variant { suite_id; _ } -> suite_id
  in
  match List.find catalog.suites ~f:(fun s -> String.equal s.id suite_id) with
  | None -> Error ("Silver suite is not in current discovery: " ^ suite_id)
  | Some suite ->
    (match target with
     | Suite _ when List.is_empty suite.cases ->
       Error ("Silver suite has no discovered cases: " ^ suite_id)
     | Suite _ -> Ok (suite, None)
     | Variant { case_id; _ } ->
       (match List.find suite.cases ~f:(fun c -> String.equal c.id case_id) with
        | None -> Error ("Silver variant is not in current discovery: " ^ suite_id ^ "/" ^ case_id)
        | Some case -> Ok (suite, Some case)))
;;

let select t view target =
  let open Result.Let_syntax in
  let%bind p = check_view t view in
  let%map _ = find_target view.catalog target in
  let t =
    Map.set t ~key:view.project ~data:{ p with confirmed = Set.add p.confirmed target }
  in
  t, { view; target }
;;

let selected_target selected = selected.target

let fields_for p target (suite : suite) =
  let saved = Map.find p.overrides target |> Option.value ~default:[] in
  let field id label default choices =
    let value = List.Assoc.find saved id ~equal:equal_field_id |> Option.value ~default in
    { id; label; value; default; choices }
  in
  field Seed "Seed" suite.default_seed []
  :: List.map suite.parameters ~f:(fun p -> field (Parameter p.key) p.label p.default p.choices)
;;

let begin_edit t selected =
  let open Result.Let_syntax in
  let%bind p = check_view t selected.view in
  let%map suite, _ = find_target selected.view.catalog selected.target in
  { selected; fields = fields_for p selected.target suite }
;;

let fields edit = edit.fields

let set_field edit field_id value =
  { edit with
    fields =
      List.map edit.fields ~f:(fun field ->
        if equal_field_id field.id field_id then { field with value } else field)
  }
;;

let reset edit =
  { edit with fields = List.map edit.fields ~f:(fun field -> { field with value = field.default }) }
;;

let non_defaults fields =
  List.filter_map fields ~f:(fun field ->
    if String.equal field.value field.default then None else Some (field.id, field.value))
;;

let valid_seed value =
  let length = String.length value in
  length >= 1
  && length <= 20
  && String.for_all value ~f:Char.is_digit
  && (length = 1 || not (Char.equal value.[0] '0'))
  && (length < 20 || String.compare value "18446744073709551615" <= 0)
;;

let validate_fields fields =
  let invalid (field : field) =
    match field.id with
    | Seed ->
      if valid_seed field.value
      then None
      else Some "Silver seed must be a canonical unsigned 64-bit decimal string"
    | Parameter key ->
      if String.length field.value > 4096 || String.contains field.value '\000'
      then Some ("Silver parameter " ^ key ^ " exceeds 4096 bytes or contains NUL")
      else if List.is_empty field.choices || List.mem field.choices field.value ~equal:String.equal
      then None
      else Some ("Invalid choice for Silver parameter " ^ key)
  in
  match List.find_map fields ~f:invalid with
  | None -> Ok ()
  | Some reason -> Error reason
;;

let apply t { selected = { view; target }; fields } =
  let open Result.Let_syntax in
  let%bind p = check_view t view in
  let%map () = validate_fields fields in
  let overrides =
    match non_defaults fields with
    | [] -> Map.remove p.overrides target
    | values -> Map.set p.overrides ~key:target ~data:values
  in
  Map.set t ~key:view.project ~data:{ p with overrides }
;;

let cancel t _ = t

type selection =
  { suite : string
  ; cases : string list
  ; seed : string
  ; parameters : (string * string) list
  }

let sexp_of_selection { suite; cases; seed; parameters } =
  let atom value = Sexp.Atom value in
  let list values = Sexp.List values in
  list
    [ list [ atom "suite"; atom suite ]
    ; list [ atom "cases"; list (List.map cases ~f:atom) ]
    ; list [ atom "seed"; atom seed ]
    ; list
        [ atom "parameters"
        ; list (List.map parameters ~f:(fun (key, value) -> list [ atom key; atom value ]))
        ]
    ; list [ atom "asic_inputs"; list [] ]
    ]
;;

type launch =
  { project : project
  ; target : target
  ; discovery_digest : string
  ; catalog_generation : int
  ; selection : selection
  ; target_label : string
  ; non_defaults : (field_id * string) list
  ; display : string
  }

let display_text text =
  let length = String.length text in
  let buf = Buffer.create length in
  let rec loop i =
    if i < length
    then (
      let u = Stdlib.String.get_utf_8_uchar text i in
      let len = Stdlib.Uchar.utf_decode_length u in
      let code = Stdlib.Uchar.utf_decode_uchar u |> Stdlib.Uchar.to_int in
      if (not (Stdlib.Uchar.utf_decode_is_valid u))
         || code < 32
         || (code >= 127 && code <= 159)
         || code = 0x2028
         || code = 0x2029
      then Buffer.add_char buf '?'
      else Buffer.add_substring buf text ~pos:i ~len;
      loop (i + len))
  in
  loop 0;
  Buffer.contents buf
;;

let resolve t { view; target } =
  let open Result.Let_syntax in
  let%bind p = check_view t view in
  let%bind suite, variant = find_target view.catalog target in
  let fields = fields_for p target suite in
  let%map () = validate_fields fields in
  let cases =
    match variant with
    | Some case -> [ case.id ]
    | None -> List.map suite.cases ~f:(fun case -> case.id)
  in
  let seed = (List.hd_exn fields).value in
  let parameters =
    List.filter_map fields ~f:(fun field ->
      match field.id with
      | Seed -> None
      | Parameter key -> Some (key, field.value))
    |> List.sort ~compare:(fun (a, _) (b, _) -> String.compare a b)
  in
  let target_label =
    let name ~id label = if String.is_empty label then id else display_text label in
    let suite = name ~id:suite.id suite.label in
    match variant with
    | None -> suite
    | Some case -> suite ^ " / " ^ name ~id:case.id case.label
  in
  let non_defaults = non_defaults fields in
  let display =
    String.concat
      ~sep:" · "
      ([ "Run test"; target_label ]
       @ List.map non_defaults ~f:(fun (field, value) ->
         let key =
           match field with
           | Seed -> "seed"
           | Parameter key -> key
         in
         display_text key ^ "=" ^ display_text value))
  in
  { project = view.project
  ; target
  ; discovery_digest = view.catalog.discovery_digest
  ; catalog_generation = view.generation
  ; selection = { suite = suite.id; cases; seed; parameters }
  ; target_label
  ; non_defaults
  ; display
  }
;;

let check_launch t (launch : launch) =
  let p = state t launch.project in
  match p.error, p.catalog with
  | Some reason, _ -> Error reason
  | None, Some catalog
    when p.generation = launch.catalog_generation
         && String.equal catalog.discovery_digest launch.discovery_digest ->
    Ok ()
  | _ -> Error stale
;;

let set_configured_default t ~project configured_default =
  update t project ~f:(fun p -> { p with configured_default })
;;

type alias =
  | Ready of launch
  | Pick_target
  | Blocked of string

let resolve_alias t ~project =
  let p = state t project in
  match Option.first_some p.configured_default p.last_launched with
  | None -> Pick_target
  | Some target ->
    (match p.error, catalog_view t ~project with
     | Some reason, _ -> Blocked reason
     | None, None -> Blocked "Discover a Silver test catalog first"
     | None, Some view ->
       (match find_target view.catalog target with
        | Error reason -> Blocked reason
        | Ok _ when p.needs_selection && not (Set.mem p.confirmed target) -> Blocked stale
        | Ok _ ->
          (match resolve t { view; target } with
           | Ok launch -> Ready launch
           | Error reason -> Blocked reason)))
;;

let record_launch t (launch : launch) =
  update t launch.project ~f:(fun p -> { p with last_launched = Some launch.target })
;;
