open! Core
open Async
module Testing = Silver_overview.Testing

let str value = `String value
let list f values = `List (List.map values ~f)

let reply kind fields =
  printf "%s\n%!" (Yojson.Safe.to_string (`Assoc (("kind", str kind) :: fields)))
;;

let reason kind message = reply kind [ "reason", str message ]

let suite_json (suite : Testing.suite) =
  let case (case : Testing.case) = `Assoc [ "id", str case.id; "label", str case.label ] in
  let parameter (p : Testing.parameter) =
    `Assoc [ "key", str p.key; "label", str p.label; "default", str p.default; "choices", list str p.choices ]
  in
  `Assoc
    [ "id", str suite.id; "label", str suite.label; "cases", list case suite.cases
    ; "parameters", list parameter suite.parameters; "default_seed", str suite.default_seed
    ]
;;

let main endpoint timeout =
  let project = ref None in
  let catalog = ref None in
  let close () =
    Option.iter !project ~f:Testing.close;
    project := None
  in
  let handle line =
    let open Yojson.Safe.Util in
    match List.map (Yojson.Safe.from_string line |> to_list) ~f:to_string with
    | [ "connect"; project_root ] ->
      close ();
      (match%map Testing.connect ~endpoint ~project_root ~timeout () with
       | Error message -> reason "error" message
       | Ok verified ->
         project := Some verified;
         reply "connected" [ "root", str (Testing.project_root verified) ])
    | [ "discover" ] ->
      (match%map Testing.discover (Option.value_exn !project) with
       | Error message -> reason "error" message
       | Ok discovered ->
         catalog := Some discovered;
         reply "catalog"
           [ "digest", str (Testing.digest discovered); "suites", list suite_json (Testing.suites discovered) ])
    | [ "launch"; suite; cases; seed; n ] ->
      let cases = if String.is_empty cases then [] else String.split cases ~on:',' in
      let parameters = if String.is_empty n then [] else [ "n", n ] in
      (match%map Testing.launch (Option.value_exn !catalog) ~suite ~cases ~seed ~parameters with
       | Accepted { attempt_id; job_id } ->
         reply "accepted" [ "attempt", str attempt_id; "job", str job_id ]
       | Stale_catalog message -> reason "stale" message
       | Rejected message -> reason "rejected" message
       | Uncertain message -> reason "uncertain" message)
    | _ -> failwithf "Unknown Testing driver command: %S" line ()
  in
  let rec loop () =
    match%bind Reader.read_line (Lazy.force Reader.stdin) with
    | `Eof ->
      close ();
      Shutdown.shutdown 0;
      Deferred.unit
    | `Ok line ->
      let%bind () = handle line in
      loop ()
  in
  loop ()
;;

let () =
  let args = Sys.get_argv () in
  let timeout = Time_ns.Span.of_int_ms (Int.of_string args.(2)) in
  don't_wait_for (main args.(1) timeout);
  never_returns (Scheduler.go ())
;;
