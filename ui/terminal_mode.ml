external capture : unit -> string = "cobalt_terminal_mode_capture"
external restore : string -> unit = "cobalt_terminal_mode_restore"

let save () =
  let snapshot = capture () in
  let restored = ref false in
  let restore_once () =
    if not !restored then (
      restore snapshot;
      restored := true)
  in
  (* Async shutdown also runs the terminal backend's cleanup. This final fallback
     runs after those hooks, including on signals and failed startup. *)
  Stdlib.at_exit (fun () -> try restore_once () with _ -> ());
  restore_once
;;
