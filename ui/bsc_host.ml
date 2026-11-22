open! Core
open! Async
module Bsc = Cobalt_app.Bsc
module Resource = Cobalt_core.Resource

type t = { mutable process : Process.t option; mutable stopped : bool }

let create () = { process = None; stopped = false }

let terminate process =
  try ignore (Signal_unix.send Signal.term (`Group (Process.pid process))
    : [ `Ok | `No_such_process ]) with _ -> ()
;;

let stop t =
  t.stopped <- true;
  Option.iter t.process ~f:terminate
;;

let prepare ({ Bsc.directory; action; dirty; _ } : Bsc.request) =
  let rec find directory =
    let path = Filename.concat directory Bsc.config_name in
    match Core_unix.lstat path with
    | _ -> directory, path
    | exception Unix.Unix_error (ENOENT, _, _) ->
      let parent = Filename.dirname directory in
      if String.equal parent directory then
        failwith (sprintf "No %s above %s. Add a project command there first." Bsc.config_name directory);
      find parent
  in
  let root, path = find directory in
  let real path = try Filename_unix.realpath path with _ -> path in
  let real_root = real root in
  List.iter dirty ~f:(fun file ->
    if Resource.within ~root file || Resource.within ~root:real_root (real file)
       || String.is_suffix file ~suffix:".bsv" || String.is_suffix file ~suffix:".bs"
    then failwith ("Save modified buffer before running BSC (checks saved files only): " ^ file));
  let fd = Core_unix.openfile path ~mode:[ O_RDONLY; O_NONBLOCK; O_CLOEXEC ] in
  let text = Exn.protect ~finally:(fun () -> Core_unix.close fd) ~f:(fun () ->
    let stat = Core_unix.fstat fd in
    if Poly.(stat.st_kind <> Core_unix.S_REG) || Int64.(stat.st_size > of_int 65536)
    then failwith (path ^ " must be a regular file of at most 64 KiB");
    let bytes = Bytes.create 65537 in
    let rec read pos =
      if pos >= Bytes.length bytes then failwith (path ^ " exceeds 64 KiB");
      match Core_unix.read fd ~buf:bytes ~pos ~len:(Bytes.length bytes - pos) with
      | 0 -> Bytes.to_string (Bytes.sub bytes ~pos:0 ~len:pos)
      | n -> read (pos + n)
    in
    read 0) in
  let command = Bsc.command action text |> Or_error.tag ~tag:path |> Or_error.ok_exn in
  root, command
;;

(* Drain both pipes in parallel, even after the capture limit. [read_line] would
   allow one oversized line to defeat that limit. Don't parse a truncated line. *)
let capture reader =
  let limit = 2 * 1024 * 1024 in
  let buffer = Buffer.create 4096 in
  let bytes = Bytes.create 8192 in
  let rec read truncated =
    match%bind Reader.read reader bytes with
    | `Eof ->
      let text = Buffer.contents buffer in
      let text = if not truncated then text else
        Option.value_map (String.rindex text '\n') ~default:"" ~f:(fun i -> String.prefix text (i + 1)) in
      return (text, truncated)
    | `Ok n ->
      let kept = Int.min n (limit - Buffer.length buffer) in
      Buffer.add_subbytes buffer bytes ~pos:0 ~len:kept;
      read (truncated || kept < n)
  in
  read false
;;

let explain = function Failure message -> message | exn -> Exn.to_string exn

let execute t (request : Bsc.request) =
  let fail ~root status : Bsc.result = { root; findings = []; success = false; status } in
  match%bind Monitor.try_with ~extract_exn:true (fun () -> In_thread.run (fun () -> prepare request)) with
  | Error exn -> return (fail ~root:request.directory (explain exn))
  | Ok (root, { program; args }) ->
    if t.stopped then return (fail ~root "Editor shutdown; command not launched") else
    let prog =
      if Filename.is_relative program && String.contains program '/' then Filename.concat root program
      else program in
    match%bind Process.create ~working_dir:root ~setpgid:Core_unix.Pgid.new_process_group ~prog ~args () with
    | Error error ->
      return (fail ~root (sprintf "Could not launch %s; check PATH or %s: %s"
        program Bsc.config_name (Error.to_string_hum error)))
    | Ok process ->
      t.process <- Some process;
      if t.stopped then terminate process;
      let%bind result = Monitor.try_with ~extract_exn:true (fun () ->
        let%bind () = Writer.close (Process.stdin process) in
        let%bind (stdout, out_truncated), (stderr, err_truncated) =
          Deferred.both (capture (Process.stdout process)) (capture (Process.stderr process)) in
        let%bind exit = Process.wait process in
        let%bind () = Deferred.all_unit [ Reader.close (Process.stdout process); Reader.close (Process.stderr process) ] in
        In_thread.run (fun () ->
          let all = Bsc.findings ~root stdout @ Bsc.findings ~root stderr in
          let findings = List.take all 1000 in
          let truncated = if out_truncated || err_truncated || List.length all > 1000
            then " (output truncated)" else "" in
          let success, status =
            match exit with
            | Ok () -> true, sprintf "Succeeded: %d findings%s" (List.length findings) truncated
            | Error exit ->
              let detail = if not (List.is_empty findings) then "" else
                let output = if String.is_empty (String.strip stderr) then stdout else stderr in
                match List.find (String.split_lines output) ~f:(fun line -> not (String.is_empty (String.strip line))) with
                | None -> "; no BSC findings or tool output"
                | Some line -> "; " ^ String.prefix (String.strip line) 400
              in
              false, sprintf "Failed (%s): %d findings%s%s" (Unix.Exit_or_signal.to_string_hum (Error exit))
                (List.length findings) truncated detail
          in
          { Bsc.root; findings; success; status })) in
      t.process <- None;
      return (match result with
        | Ok result -> result
        | Error exn -> fail ~root ("Could not read compiler result: " ^ explain exn))
;;
