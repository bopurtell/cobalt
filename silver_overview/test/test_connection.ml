open! Core
open Async
module Connection = Silver_connection

let ok = function
  | Ok value -> value
  | Error reason -> failwith reason
;;

let path directory = Filename.concat directory "daemon.sexp"

let endpoint = "http://127.0.0.1:41234"

let metadata ?(endpoint = endpoint) ?(pid = 124) () =
  sprintf "((endpoint %s)(instance_id actual-daemon)(pid %d))" endpoint pid
;;

let write directory data =
  Out_channel.write_all (path directory) ~data;
  Core_unix.chmod (path directory) ~perm:0o600
;;

let test_explicit () =
  let candidate = Connection.explicit "  http://localhost:00080/  " |> ok in
  assert (String.equal (Connection.endpoint candidate) "http://localhost:80");
  assert (Poly.equal (Connection.source candidate) Explicit);
  assert (Result.is_ok (Connection.explicit "http://[::1]:65535"));
  List.iter
    [ ""; "http://localhost"; "https://127.0.0.1:80"; "http://127.0.0.2:80"
    ; "http://example.com:80"; "http://localhost:80/path"; "http://localhost:80?x"
    ; "http://localhost:80#h"; "http://localhost:0"; "http://localhost:65536"
    ; "http://localhost:80@127.0.0.1"; "http://localhost:80\r\nHost: example.com"
    ]
    ~f:(fun input -> assert (Result.is_error (Connection.explicit input)))
;;

let test_lookup directory =
  let known = [ "http://example.com:80"; "http://localhost:41234/"; "http://[::1]:9000" ] in
  let%bind missing = Connection.lookup ~directory ~known () in
  assert (Option.is_none missing.advertisement_error);
  assert (List.length missing.candidates = 2);
  assert (not (Sys_unix.file_exists_exn (path directory)));
  write directory (metadata ());
  let%bind found = Connection.lookup ~directory ~known () in
  Option.iter found.advertisement_error ~f:failwith;
  assert (
    Poly.equal
      (List.map found.candidates ~f:(fun c -> Connection.endpoint c, Connection.source c))
      [ endpoint, Connection.Advertised; "http://[::1]:9000", Connection.Known ]);
  let advertised = List.hd_exn found.candidates in
  let rec test_malformed = function
    | [] -> return ()
    | value :: rest ->
      write directory value;
      let%bind result = Connection.lookup ~directory ~known () in
      assert (Option.is_some result.advertisement_error);
      assert (List.length result.candidates = 2);
      assert (List.for_all result.candidates ~f:(fun c -> Poly.equal (Connection.source c) Known));
      test_malformed rest
  in
  let%bind () =
    test_malformed
      [ "((endpoint broken))"; metadata ~endpoint:"http://example.com:90" ()
      ; metadata ~pid:0 ()
      ; "((endpoint http://127.0.0.1:41234)(instance_id \"a\\000b\")(pid 124))"
      ; String.make 8193 'x'
      ]
  in
  Core_unix.unlink (path directory);
  Core_unix.mkfifo (path directory) ~perm:0o600;
  let%bind fifo = Connection.lookup ~directory () in
  assert (Option.is_some fifo.advertisement_error);
  Core_unix.unlink (path directory);
  Core_unix.symlink ~target:"missing" ~link_name:(path directory);
  let%map symlink = Connection.lookup ~directory () in
  assert (Option.is_some symlink.advertisement_error);
  Core_unix.unlink (path directory);
  advertised
;;

let test_paths directory =
  let runtime = Filename.concat directory "runtime" in
  let state = Filename.concat directory "state" in
  let home = Filename.concat directory "home" in
  let home_state = Filename.concat home ".local/state" in
  List.iter [ runtime; state; home; Filename.concat home ".local"; home_state ]
    ~f:(fun dir -> Core_unix.mkdir dir ~perm:0o700);
  let destinations = [ runtime; state; home_state ] in
  List.iteri destinations ~f:(fun i root ->
    let published = Filename.concat root "hardcaml-workbench" in
    Core_unix.mkdir published ~perm:0o700;
    write published (metadata ~endpoint:(sprintf "http://127.0.0.1:%d" (9000 + i)) ()));
  let check ~runtime ~state index =
    let%map result =
      Process.run
        ~prog:Sys.executable_name
        ~args:[ "--check-default-path"; sprintf "http://127.0.0.1:%d" (9000 + index) ]
        ~env:(`Extend [ "XDG_RUNTIME_DIR", runtime; "XDG_STATE_HOME", state; "HOME", home ])
        ()
    in
    Or_error.ok_exn result |> ignore
  in
  Monitor.protect
    (fun () ->
      let%bind () = check ~runtime ~state 0 in
      let%bind () = check ~runtime:"" ~state 1 in
      check ~runtime:"" ~state:"" 2)
    ~finally:(fun () ->
      List.iter destinations ~f:(fun root ->
        let published = Filename.concat root "hardcaml-workbench" in
        Core_unix.unlink (path published);
        Core_unix.rmdir published);
      List.iter [ runtime; state; home_state; Filename.concat home ".local"; home ] ~f:Core_unix.rmdir;
      return ())
;;

let test_connect advertised =
  let project_root = "/work/fifo" in
  let handshake candidate ~instance ~capabilities ~server_root =
    let seen = ref [] in
    let peer ~endpoint:requested ~timeout:_ ~stop:_ ({ path; _ } : Silver_overview.request) =
      assert (String.equal requested (Connection.endpoint candidate));
      seen := path :: !seen;
      let body =
        match path with
        | "/api/hello" ->
          sprintf "((protocol_versions (1))(instance_id %s)(capabilities (%s)))"
            instance capabilities
        | "/api/v1/open-project" ->
          sprintf "(Ok ((project ((id fifo)(root ((path %s)))))))" server_root
        | _ -> failwith "Unexpected RPC"
      in
      return (Ok ({ status = 200; body } : Silver_overview.response))
    in
    let%map result = Connection.connect ~peer candidate ~project_root in
    result, List.rev !seen
  in
  let%bind stale, requests =
    handshake advertised ~instance:"different" ~capabilities:"simulation" ~server_root:project_root
  in
  assert (Result.is_error stale);
  assert (Poly.equal requests [ "/api/hello" ]);
  let%bind unsupported, requests =
    handshake advertised ~instance:"actual-daemon" ~capabilities:"updates" ~server_root:project_root
  in
  assert (Result.is_error unsupported);
  assert (Poly.equal requests [ "/api/hello" ]);
  let%bind good, requests =
    handshake advertised ~instance:"actual-daemon" ~capabilities:"simulation" ~server_root:project_root
  in
  let good = ok good in
  assert (String.equal (Silver_overview.Testing.project_root good) project_root);
  assert (Poly.equal requests [ "/api/hello"; "/api/v1/open-project" ]);
  Silver_overview.Testing.close good;
  let explicit = Connection.explicit endpoint |> ok in
  let%bind explicit_project, requests =
    handshake explicit ~instance:"different" ~capabilities:"simulation" ~server_root:project_root
  in
  Silver_overview.Testing.close (ok explicit_project);
  assert (Poly.equal requests [ "/api/hello"; "/api/v1/open-project" ]);
  let%map wrong_root, _ =
    handshake explicit ~instance:"different" ~capabilities:"simulation" ~server_root:"/work/other"
  in
  assert (Result.is_error wrong_root)
;;

let test_shares directory =
  let module Share = Connection.Share in
  let file = Filename.concat directory "shares.sexp" in
  let project_root = "/work/other project" in
  let row ?(instance = "actual-daemon") ?(project = "fifo") name =
    sprintf "((offer_id %s)(endpoint %s)(instance_id %s)(project_id %s)(project_root %S))"
      name endpoint instance project project_root
  in
  let publish rows =
    Out_channel.write_all file ~data:("(cobalt-share-fixture-v1 " ^ String.concat ~sep:" " rows ^ ")");
    Core_unix.chmod file ~perm:0o600
  in
  let lookup () = Share.lookup ~file in
  let%bind absent = lookup () in
  assert (List.is_empty absent.shares && Option.is_none absent.error);
  publish [ row "left"; row ~instance:"other-daemon" "right"; "(broken)" ];
  let%bind mixed = lookup () in
  assert (Option.is_some mixed.error);
  assert (List.equal String.equal (List.map mixed.shares ~f:Share.offer_id) [ "left"; "right" ]);
  let selected = List.hd_exn mixed.shares in
  assert (String.equal (Share.project_root selected) project_root);
  assert (String.equal (Share.project_id selected) "fifo");
  let attempt
      ?(instance = "actual-daemon") ?(root = project_root) ?(id = "fifo")
      ?(snapshot_instance = "actual-daemon")
      ?(unreachable = false) ?(before_snapshot_reply = ignore) () =
    let seen = ref [] in
    let peer ~endpoint:requested ~timeout:_ ~stop:_ ({ path; body; _ } : Silver_overview.request) =
      assert (String.equal requested endpoint);
      seen := path :: !seen;
      if unreachable then return (Error "unreachable")
      else
        let body =
          match path with
          | "/api/hello" ->
            sprintf "((protocol_versions (1))(instance_id %s)(capabilities (simulation)))" instance
          | "/api/v1/snapshot" ->
            assert (Sexp.equal (Sexp.of_string body) (Sexp.of_string "((instance_id actual-daemon))"));
            before_snapshot_reply ();
            let project id root = sprintf "((id %s)(root ((path %S))))" id root in
            sprintf "(Ok ((projects (%s %s))(cursor ((instance_id %s)(sequence 0)))))"
              (project "other" project_root) (project id root) snapshot_instance
          | _ -> failwith ("Unexpected share RPC: " ^ path)
        in
        return (Ok ({ status = 200; body } : Silver_overview.response))
    in
    let%map result = Share.connect ~peer selected in
    result, List.rev !seen
  in
  let hello = [ "/api/hello" ] in
  let verification = hello @ [ "/api/v1/snapshot" ] in
  let%bind good, seen = attempt () in
  let good = ok good in
  assert (String.equal (Silver_overview.Testing.project_root good) project_root);
  assert (String.equal (Silver_overview.Testing.project_id good) "fifo");
  assert (String.equal (Silver_overview.Testing.instance_id good) "actual-daemon");
  Silver_overview.Testing.close good;
  assert (Poly.equal seen verification);
  let reject result expected =
    let%map result, seen = result in
    assert (Result.is_error result && Poly.equal seen expected)
  in
  let%bind () = reject (attempt ~instance:"replacement" ()) hello in
  let%bind () = reject (attempt ~unreachable:true ()) hello in
  let%bind () = reject (attempt ~snapshot_instance:"replacement" ()) verification in
  let%bind () = reject (attempt ~root:"/work/wrong" ()) verification in
  let%bind () = reject (attempt ~id:"replacement" ()) verification in
  let%bind () =
    reject (attempt ~before_snapshot_reply:(fun () -> publish [ row "right" ]) ()) verification
  in
  let%bind () = reject (attempt ()) [] in
  publish [ row ~project:"changed" "left"; row "right" ];
  let%bind () = reject (attempt ()) [] in
  publish [ row "left"; row "left"; row "right" ];
  let%bind duplicated = lookup () in
  assert (Option.is_some duplicated.error);
  assert (List.equal String.equal (List.map duplicated.shares ~f:Share.offer_id) [ "right" ]);
  let%bind () = reject (attempt ()) [] in
  publish [ row "left" ];
  Core_unix.chmod file ~perm:0o666;
  let%bind unsafe = lookup () in
  assert (List.is_empty unsafe.shares && Option.is_some unsafe.error);
  Core_unix.unlink file;
  Core_unix.symlink ~target:"not-a-fixture" ~link_name:file;
  let%map symlink = lookup () in
  assert (List.is_empty symlink.shares && Option.is_some symlink.error);
  Core_unix.unlink file
;;

let test_live_shares directory =
  let module Share = Connection.Share in
  let shares = Filename.concat directory "editor-shares" in
  let registry = Filename.concat shares "v1" in
  let lookup () = Share.lookup_live ~directory () in
  let%bind missing = lookup () in
  assert (List.is_empty missing.shares && Option.is_none missing.error);
  List.iter [ shares; registry ] ~f:(fun path -> Core_unix.mkdir path ~perm:0o700);
  let id n = sprintf "%032x" n in
  let path n = Filename.concat registry (id n ^ ".sexp") in
  let write ?(mode = "embedded") ?(field_id = None) ?(perm = 0o600) ?(locked = true) n =
    let temporary = Filename.concat registry ".prepublish" in
    let fd = Core_unix.openfile temporary ~mode:[ O_CREAT; O_EXCL; O_WRONLY ] ~perm in
    Core_unix.fchmod fd ~perm;
    let body =
      sprintf "(silver-editor-share-v1 ((offer_id %s)(endpoint %s)(instance_id actual-daemon)\
               (project_id fifo)(project_root \"/work/the project\")(mode %s)))"
        (Option.value field_id ~default:(id n)) endpoint mode
    in
    assert (Core_unix.write_substring fd ~buf:body = String.length body);
    if locked
    then assert (Core_unix.flock fd Core_unix.Flock_command.lock_exclusive);
    Core_unix.rename ~src:temporary ~dst:(path n);
    fd
  in
  let one = write 1 in
  let two = write ~mode:"attached" 2 in
  Core_unix.close (write ~locked:false 3);
  let wrong_id = write ~field_id:(Some (id 2)) 4 in
  let bad_mode = write ~mode:"detached" 5 in
  let unsafe = write ~perm:0o644 6 in
  Core_unix.symlink ~target:(path 1) ~link_name:(path 7);
  Core_unix.mkfifo (path 8) ~perm:0o600;
  let extra = Filename.concat registry "temporary" in
  Out_channel.write_all extra ~data:"Not an offer";
  let%bind found = lookup () in
  assert (Option.is_some found.error);
  assert (
    Poly.equal (List.map found.shares ~f:(fun s -> Share.offer_id s, Share.mode s))
      [ id 1, Some Share.Embedded; id 2, Some Share.Attached ]);
  let selected = List.hd_exn found.shares in
  let seen = ref [] in
  let peer ?(at_snapshot = ignore) () ~endpoint:_ ~timeout:_ ~stop:_
      ({ path; _ } : Silver_overview.request) =
    seen := path :: !seen;
    let body =
      match path with
      | "/api/hello" ->
        "((protocol_versions (1))(instance_id actual-daemon)(capabilities (simulation)))"
      | "/api/v1/snapshot" ->
        at_snapshot ();
        "(Ok ((projects (((id fifo)(root ((path \"/work/the project\"))))))\
         (cursor ((instance_id actual-daemon)(sequence 0)))))"
      | _ -> failwith path
    in
    return (Ok ({ status = 200; body } : Silver_overview.response))
  in
  let%bind connected = Share.connect ~peer:(peer ()) selected in
  Silver_overview.Testing.close (ok connected);
  let rpcs = [ "/api/v1/snapshot"; "/api/hello" ] in
  assert (Poly.equal !seen rpcs);
  seen := [];
  let replacement = ref None in
  let%bind replaced =
    Share.connect selected ~peer:(peer ~at_snapshot:(fun () ->
      Core_unix.unlink (path 1);
      replacement := Some (write 1)) ())
  in
  assert (Result.is_error replaced && Poly.equal !seen rpcs);
  seen := [];
  let%bind rejected = Share.connect ~peer:(peer ()) selected in
  assert (Result.is_error rejected && List.is_empty !seen);
  let second = List.last_exn found.shares in
  Core_unix.close two;
  let%bind stale = Share.connect ~peer:(peer ()) second in
  assert (Result.is_error stale && List.is_empty !seen);
  let moved = registry ^ "-moved" in
  Core_unix.rename ~src:registry ~dst:moved;
  Core_unix.symlink ~target:moved ~link_name:registry;
  let%bind symlink = lookup () in
  assert (List.is_empty symlink.shares && Option.is_some symlink.error);
  Core_unix.unlink registry;
  Core_unix.rename ~src:moved ~dst:registry;
  Core_unix.chmod shares ~perm:0o755;
  let%bind public_parent = lookup () in
  assert (List.is_empty public_parent.shares && Option.is_some public_parent.error);
  Core_unix.chmod shares ~perm:0o700;
  let junk i = Filename.concat registry (sprintf "ignored-%d" i) in
  for i = 1 to 256 do Out_channel.write_all (junk i) ~data:"" done;
  let%map capped = lookup () in
  assert (List.is_empty capped.shares && Option.is_some capped.error);
  for i = 1 to 256 do Core_unix.unlink (junk i) done;
  List.iter [ one; Option.value_exn !replacement; wrong_id; bad_mode; unsafe ] ~f:Core_unix.close;
  for i = 1 to 8 do Core_unix.unlink (path i) done;
  Core_unix.unlink extra;
  Core_unix.rmdir registry;
  Core_unix.rmdir shares
;;

let main () =
  let directory = Filename.concat Filename.temp_dir_name "cobalt-silver-discovery" in
  let directory = Core_unix.mkdtemp directory in
  test_explicit ();
  let%bind advertised = test_lookup directory in
  let%bind () = test_paths directory in
  let%bind () = test_shares directory in
  Core_unix.rmdir directory;
  (* Dune's test sandbox can set TMPDIR to a group-writable ancestor,
     which the live reader correctly refuses. Use a private directory under
     the system temp parent instead, or an explicitly supplied safe parent. *)
  let parent = Option.value (Sys.getenv "COBALT_TEST_SHARE_TMPDIR") ~default:"/tmp" in
  let live = Core_unix.mkdtemp (Filename.concat (Filename_unix.realpath parent) "cobalt-share") in
  let%bind () = test_live_shares live in
  Core_unix.rmdir live;
  test_connect advertised
;;

let () =
  let check expected =
    let%map found = Connection.lookup () in
    assert (List.equal String.equal (List.map found.candidates ~f:Connection.endpoint) [ expected ])
  in
  let run =
    match Array.to_list (Sys.get_argv ()) with
    | [ _; "--check-default-path"; expected ] -> check expected
    | _ -> main ()
  in
  don't_wait_for (run >>| fun () -> Shutdown.shutdown 0);
  never_returns (Scheduler.go ())
;;
