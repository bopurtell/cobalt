open! Core
open! Async

module Pool = Cobalt_terminal_pool
module Model = Pool.Model

let check condition message = if not condition then failwith message

let command pool number text =
  Pool.submit pool
    [ number, Model.Paste text
    ; number, Model.Key { code = Enter; modifiers = Model.no_modifiers }
    ]
;;

let contains (snapshot : Model.snapshot) text =
  Array.exists snapshot.rows ~f:(fun row ->
    let line = Array.map row ~f:(fun (cell : Model.cell) -> cell.text)
               |> String.concat_array in
    String.is_substring line ~substring:text)
;;

let rec wait_screen pool ~number ~generation ~matches =
  let%bind update = Pool.next_update pool in
  match update with
  | None -> failwith "pool closed before the expected screen"
  | Some (_, _, Model.Failed message) -> failwith message
  | Some (n, g, Model.Snapshot snapshot)
    when n = number && g = generation && matches snapshot -> return snapshot
  | Some _ -> wait_screen pool ~number ~generation ~matches
;;

let rec poll predicate =
  if predicate () then return ()
  else (
    let%bind () = Clock_ns.after (Time_ns.Span.of_ms 10.) in
    poll predicate)
;;

let proc_stat pid = sprintf "/proc/%d/stat" pid

let job_running pid =
  match In_channel.read_all (proc_stat pid) with
  | stat ->
    let after_name = String.rindex_exn stat ')' + 2 in
    not (Char.equal stat.[after_name] 'Z')
  | exception Sys_error _ -> false
;;

let run pool cwd =
  let path name = Filename.concat cwd name in
  let start = Model.Start { cwd; rows = 10; cols = 100 } in
  check
    (match Pool.submit pool [ 2, start; 0, start ] with
     | exception Invalid_argument _ -> true
     | () -> false)
    "nonpositive terminal number was accepted";
  Pool.submit pool [ 2, start; 70, start ];
  command pool 2
    "stty -echo; OWNER=two; i=0; while [ \"$i\" -lt 12000 ]; do printf 'line %s\\n' \"$i\"; i=$((i+1)); done; printf 'HIDDEN_%s\\n' COMPLETE; : > flood-done";
  command pool 70 "stty -echo; OWNER=seventy";
  (* No reads from the pool until the shell completes a flood substantially
     larger than the PTY buffer. The completion file is out-of-band. *)
  let%bind () = poll (fun () -> Stdlib.Sys.file_exists (path "flood-done")) in
  let%bind _ = wait_screen pool ~number:2 ~generation:1
      ~matches:(fun s -> contains s "HIDDEN_COMPLETE") in
  Pool.submit pool [ 2, start ];
  command pool 2 "printf 'REOPEN_%s\\n' \"$OWNER\"";
  let%bind _ = wait_screen pool ~number:2 ~generation:1
      ~matches:(fun s -> contains s "REOPEN_two") in
  Pool.submit pool [ 2, Model.Stop ];
  let%bind _ = wait_screen pool ~number:2 ~generation:1
      ~matches:(fun s -> Option.is_some s.exited) in
  command pool 70 "printf 'OTHER_%s\\n' \"$OWNER\"";
  let%bind _ = wait_screen pool ~number:70 ~generation:1
      ~matches:(fun s -> contains s "OTHER_seventy") in
  Pool.submit pool [ 2, start ];
  command pool 2 "stty -echo; printf 'RESTART_%s\\n' \"${OWNER:-fresh}\"";
  let%bind _ = wait_screen pool ~number:2 ~generation:2
      ~matches:(fun s -> contains s "RESTART_fresh") in
  let stubborn number file =
    command pool number
      ("trap '' HUP; (while :; do sleep 30; done) & "
       ^ "printf '%s %s\\n' \"$$\" \"$!\" > " ^ file ^ "; wait")
  in
  stubborn 2 "pids-2";
  stubborn 70 "pids-70";
  let%bind children =
    Deferred.List.map [ "pids-2"; "pids-70" ] ~how:`Sequential ~f:(fun file ->
      let pids () =
        match In_channel.read_all (path file) |> String.strip |> String.split ~on:' ' with
        | [ shell; job ] ->
          Option.both (Int.of_string_opt shell) (Int.of_string_opt job)
        | _ -> None
        | exception Sys_error _ -> None
      in
      let%bind () = poll (fun () -> Option.is_some (pids ())) in
      let shell, job = Option.value_exn (pids ()) in
      check (job_running shell && job_running job) "shutdown fixture not running";
      return (shell, job))
  in
  let shutdown = Pool.shutdown pool in
  let%bind result = Clock_ns.with_timeout (Time_ns.Span.of_int_sec 3) (Pool.shutdown pool) in
  check (match result with `Result () -> true | `Timeout -> false) "pool shutdown did not finish";
  check (Deferred.is_determined shutdown) "initial shutdown did not finish";
  List.iter children ~f:(fun (shell, _) ->
    check (not (Stdlib.Sys.file_exists (proc_stat shell))) "shell was not reaped");
  let%bind () = poll (fun () -> List.for_all children ~f:(fun (_, job) -> not (job_running job))) in
  Pool.submit pool [ 2, start ];
  let%bind update = Pool.next_update pool in
  check (Option.is_none update) "closed pool delivered another update";
  let empty = Pool.create () in
  let pending = Pool.next_update empty in
  check (not (Deferred.is_determined pending)) "idle pool did not wait";
  let%bind () = Pool.shutdown empty in
  let%bind update = pending in
  check (Option.is_none update) "shutdown did not close a pending read";
  print_endline "numbered terminal pool smoke passed";
  return ()
;;

(* Set the fixture's environment before starting the scheduler. *)
let[@alert "-unsafe_multidomain"] () =
  Core_unix.putenv ~key:"SHELL" ~data:"/bin/sh";
  Core_unix.putenv ~key:"PS1" ~data:"";
  Core_unix.putenv ~key:"ENV" ~data:"/dev/null"
;;

let main () =
  let cwd = Core_unix.mkdtemp
      (Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "cobalt-pool-") in
  let pool = Pool.create () in
  Monitor.protect
    (fun () ->
      match%map Clock_ns.with_timeout (Time_ns.Span.of_int_sec 15) (run pool cwd) with
      | `Result () -> ()
      | `Timeout -> failwith "numbered terminal pool smoke timed out")
    ~finally:(fun () ->
      let%map () = Pool.shutdown pool in
      Array.iter (Stdlib.Sys.readdir cwd) ~f:(fun name ->
        Core_unix.unlink (Filename.concat cwd name));
      Core_unix.rmdir cwd)
;;

let () =
  don't_wait_for
    (let%bind result = Monitor.try_with main in
     match result with
     | Ok () -> Shutdown.exit 0
     | Error exn ->
       eprintf "%s\n%!" (Exn.to_string exn);
       Shutdown.exit 1);
  never_returns (Scheduler.go ())
;;
