open! Core
open Silver_quick_launch

let project = { endpoint = "http://127.0.0.1:8900"; project_root = "/projects/fifo" }
let other_root = { project with project_root = "/projects/other" }
let other_endpoint = { project with endpoint = "http://127.0.0.1:8901" }

let suite : suite =
  { id = "fifo"
  ; label = "FIFO"
  ; cases = [ { id = "directed"; label = "Directed" }; { id = "seeded"; label = "seeded" } ]
  ; parameters =
      [ { key = "n"; label = "Cycles"; default = "10"; choices = [] }
      ; { key = "mode"; label = "Mode"; default = "fast"; choices = [ "fast"; "slow" ] }
      ]
  ; default_seed = "42"
  }
;;

let catalog = { discovery_digest = "d1"; suites = [ suite; { suite with id = "other" } ] }
let suite_target = Suite "fifo"
let variant = Variant { suite_id = "fifo"; case_id = "seeded" }
let sibling = Variant { suite_id = "fifo"; case_id = "directed" }
let other_suite = Variant { suite_id = "other"; case_id = "seeded" }
let n = Parameter "n"

let ok = function
  | Ok x -> x
  | Error message -> failwith message
;;

let select_row t ?(project = project) target =
  select t (Option.value_exn (catalog_view t ~project)) target |> ok
;;

let ready = function
  | Ready launch -> launch
  | Pick_target -> failwith "Unexpected picker"
  | Blocked message -> failwith message
;;

let expect_picker t =
  match resolve_alias t ~project with
  | Pick_target -> ()
  | Ready _ | Blocked _ -> failwith "Expected the test picker"
;;

let expect_blocked t ~message =
  match resolve_alias t ~project with
  | Blocked actual when String.is_substring actual ~substring:message -> ()
  | Blocked actual -> failwith ("Unexpected blocked reason: " ^ actual)
  | Ready _ | Pick_target -> failwith "Expected unavailable exact test alias"
;;

let expect_n launch expected =
  assert (
    String.equal
      (List.Assoc.find_exn launch.selection.parameters "n" ~equal:String.equal)
      expected)
;;

let initial () = set_catalog empty ~project catalog

let test_settings () =
  let t = initial () in
  let t, v = select_row t variant in
  let edit = begin_edit t v |> ok in
  let draft = set_field edit n "50" in
  expect_n (resolve t v |> ok) "10";
  expect_n (resolve (cancel t draft) v |> ok) "10";
  let t = apply t draft |> ok in
  expect_picker t;
  let t, v = select_row t variant in
  let launch = resolve t v |> ok in
  expect_n launch "50";
  assert (String.equal launch.display "Run test · FIFO / seeded · n=50");
  assert (Poly.equal launch.non_defaults [ n, "50" ]);
  assert (String.equal launch.discovery_digest "d1");
  assert (
    Sexp.equal
      (sexp_of_selection launch.selection)
      (Sexp.of_string
         "((suite fifo)(cases (seeded))(seed 42)(parameters ((mode fast)(n 50)))(asic_inputs ()))"));
  let t, s = select_row t suite_target in
  let suite_launch = resolve t s |> ok in
  assert (List.equal String.equal suite_launch.selection.cases [ "directed"; "seeded" ]);
  expect_n suite_launch "10";
  let t = apply t (set_field (ok (begin_edit t s)) n "70") |> ok in
  expect_n (resolve t s |> ok) "70";
  expect_n (resolve t v |> ok) "50";
  List.iter [ sibling; other_suite ] ~f:(fun target ->
    let t, row = select_row t target in
    expect_n (resolve t row |> ok) "10");
  List.iter [ other_root; other_endpoint ] ~f:(fun project ->
    let t = set_catalog t ~project catalog in
    let t, row = select_row t ~project variant in
    expect_n (resolve t row |> ok) "10");
  let t = apply t (reset (ok (begin_edit t v))) |> ok in
  let launch = resolve t v |> ok in
  expect_n launch "10";
  assert (List.is_empty launch.non_defaults)
;;

let test_validation () =
  let t, row = select_row (initial ()) variant in
  let edit = begin_edit t row |> ok in
  List.iter [ ""; "-1"; "01"; "18446744073709551616" ] ~f:(fun value ->
    assert (Result.is_error (apply t (set_field edit Seed value))));
  let max_seed = "18446744073709551615" in
  let t = apply t (set_field edit Seed max_seed) |> ok in
  assert (String.equal (resolve t row |> ok).selection.seed max_seed);
  let edit = begin_edit t row |> ok in
  assert (Result.is_error (apply t (set_field edit (Parameter "mode") "unknown")));
  assert (Result.is_error (apply t (set_field edit n (String.make 4097 'n'))));
  assert (Result.is_error (apply t (set_field edit n "\000")));
  let t = apply t (set_field edit n "x\ny\027z") |> ok in
  let launch = resolve t row |> ok in
  expect_n launch "x\ny\027z";
  assert (String.equal launch.display ("Run test · FIFO / seeded · seed=" ^ max_seed ^ " · n=x?y?z"))
;;

let test_alias () =
  let t, row = select_row (initial ()) variant in
  let t = apply t (set_field (ok (begin_edit t row)) n "50") |> ok in
  expect_picker t;
  let t = record_launch t (resolve t row |> ok) in
  let t, _ = select_row t sibling in
  expect_n (ready (resolve_alias t ~project)) "50";
  let t = set_configured_default t ~project (Some suite_target) in
  let launch = ready (resolve_alias t ~project) in
  assert (Poly.equal launch.target suite_target);
  expect_n launch "10";
  let t = set_configured_default t ~project (Some (Suite "missing")) in
  expect_blocked t ~message:"missing";
  let t = set_configured_default t ~project None in
  assert (Poly.equal (ready (resolve_alias t ~project)).target variant);
  assert (Poly.equal (resolve_alias t ~project:other_root) Pick_target);
  let t = set_configured_default empty ~project (Some variant) in
  expect_blocked t ~message:"Discover";
  let t = set_catalog t ~project catalog in
  assert (Poly.equal (ready (resolve_alias t ~project)).target variant)
;;

let test_fresh_selection () =
  let t = initial () in
  let view = Option.value_exn (catalog_view t ~project) in
  let t, row = select t view variant |> ok in
  let t = apply t (set_field (ok (begin_edit t row)) n "50") |> ok in
  let launch = resolve t row |> ok in
  let t = record_launch t launch in
  let unchanged = set_catalog t ~project catalog in
  assert (Result.is_ok (resolve unchanged row));
  assert (Result.is_ok (check_launch unchanged launch));
  let t = invalidate_catalog t ~project ~reason:"Stale or unreachable" in
  expect_blocked t ~message:"Stale or unreachable";
  let stale_view = Option.value_exn (catalog_view t ~project) in
  assert (Result.is_error (select t stale_view variant));
  let t = set_catalog t ~project catalog in
  assert (Result.is_error (select t stale_view variant));
  assert (Result.is_error (resolve t row));
  assert (Result.is_error (check_launch t launch));
  let fresh = { catalog with discovery_digest = "d2" } in
  let t = set_catalog t ~project fresh in
  expect_blocked t ~message:"select the target again";
  assert (Result.is_error (select t view variant));
  assert (Result.is_error (resolve t row));
  assert (Result.is_error (apply t (ok (begin_edit unchanged row))));
  let t, _ = select_row t sibling in
  expect_blocked t ~message:"select the target again";
  let t, _ = select_row t variant in
  let launch = ready (resolve_alias t ~project) in
  expect_n launch "50";
  assert (String.equal launch.discovery_digest "d2");
  let removed = { discovery_digest = "d3"; suites = [] } in
  let t = set_catalog t ~project removed in
  expect_blocked t ~message:"not in current discovery"
;;

let test_changed_fields () =
  let t, row = select_row (initial ()) variant in
  let edit = begin_edit t row |> ok in
  let t = apply t (set_field edit (Parameter "mode") "slow") |> ok in
  let parameters =
    List.map suite.parameters ~f:(fun p ->
      if String.equal p.key "mode" then { p with choices = [ "fast" ] } else p)
  in
  let t =
    set_catalog t ~project { discovery_digest = "d2"; suites = [ { suite with parameters } ] }
  in
  let t, row = select_row t variant in
  assert (Result.is_error (resolve t row));
  let edit = begin_edit t row |> ok in
  let mode =
    List.find_exn (fields edit) ~f:(fun f -> Poly.equal f.id (Parameter "mode"))
  in
  assert (String.equal mode.value "slow");
  let t = apply t (reset edit) |> ok in
  assert (Result.is_ok (resolve t row))
;;

let () =
  test_settings ();
  test_validation ();
  test_alias ();
  test_fresh_selection ();
  test_changed_fields ()
;;
