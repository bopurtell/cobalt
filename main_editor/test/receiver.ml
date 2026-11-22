open! Core
open Async

module Transport = Cobalt_main_editor
module Location = Transport.Open_location

let on_request (request : Location.request) =
  match request.relative_file with
  | "never" -> Deferred.never ()
  | "throw" -> failwith "adapter threw"
  | "exited" -> return (Error Location.Session_exited)
  | "missing" -> return (Error (Location.Target_unavailable (Error.of_string "test missing")))
  | "bad-position" -> return (Error (Location.Invalid_position (Error.of_string "test bad position")))
  | "../outside" -> return (Error (Location.Invalid_relative_file request.relative_file))
  | _ ->
    (match request.position with
     | None -> printf "file:%s\n%!" request.relative_file
     | Some { line; column } -> printf "location:%s:%d:%d\n%!" request.relative_file line column);
    return (Ok ())
;;

let () =
  let root = (Sys.get_argv ()).(1) in
  don't_wait_for (
    match%bind Transport.start ~project_root:root ~on_request with
    | Error error ->
      eprintf "%s\n%!" (Error.to_string_hum error);
      Shutdown.shutdown 3;
      Deferred.unit
    | Ok listener ->
      printf "ready\n%!";
      let%bind (_ : string Reader.Read_result.t) = Reader.read_line (Lazy.force Reader.stdin) in
      let%bind () = Transport.stop listener in
      let%map () = Transport.stop listener in
      Shutdown.shutdown 0);
  never_returns (Scheduler.go ())
;;
