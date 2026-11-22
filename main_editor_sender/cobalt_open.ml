open! Core
open Async

module Transport = Cobalt_main_editor

let usage = "Usage: cobalt-open --project /absolute/project relative/file [LINE [COLUMN]]"

let coordinate value =
  if not (String.for_all value ~f:Char.is_digit) then failwith "Expected a positive decimal coordinate";
  match Int.of_string_opt value with
  | Some parsed when parsed > 0 -> parsed
  | _ -> failwith "Expected a positive decimal coordinate"
;;

let parse args : Transport.Open_location.request =
  let position : Transport.Open_location.position option =
    match args with
    | [ _; _; _ ] -> None
    | [ _; _; _; line ] -> Some { line = coordinate line; column = 1 }
    | [ _; _; _; line; column ] -> Some { line = coordinate line; column = coordinate column }
    | _ -> failwith usage
  in
  match args with
  | "--project" :: project_root :: relative_file :: _ ->
    if Filename.is_relative project_root then failwith "The project root must be absolute";
    { project_root; relative_file; position }
  | _ -> failwith usage
;;

let report label error =
  let message = Error.to_string_hum error in
  if String.exists message ~f:(fun c -> Char.to_int c < 32 || Char.to_int c = 127)
  then Stdlib.Printf.eprintf "cobalt-open: %s: %S\n%!" label message
  else Stdlib.Printf.eprintf "cobalt-open: %s: %s\n%!" label message
;;

let () =
  let args = Array.to_list (Sys.get_argv ()) |> List.tl_exn in
  match args with
  | [ "--help" ] | [ "-h" ] -> Stdlib.Printf.printf "%s\n%!" usage
  | _ ->
    match Or_error.try_with (fun () -> parse args) with
    | Error error ->
      report "invalid arguments" error;
      Stdlib.exit 2
    | Ok request ->
      don't_wait_for (
        let%map reply = Transport.send request in
        (match reply with
         | Ok (Ok ()) -> Stdlib.Printf.printf "Opened\n%!"; Shutdown.shutdown 0
         | Ok (Error failure) ->
           report "editor rejected location" (Transport.Open_location.to_error failure);
           Shutdown.shutdown 1
         | Error error -> report "transport failed" error; Shutdown.shutdown 2));
      never_returns (Scheduler.go ())
;;
