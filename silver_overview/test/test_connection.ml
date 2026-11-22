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

let main () =
  let directory = Filename.concat Filename.temp_dir_name "cobalt-silver-discovery" in
  let directory = Core_unix.mkdtemp directory in
  test_explicit ();
  let%bind advertised = test_lookup directory in
  let%bind () = test_paths directory in
  Core_unix.rmdir directory;
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
