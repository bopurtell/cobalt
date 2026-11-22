open Bonsai_term
open Bonsai.Let_syntax

module Session = Cobalt_app.Session
module Location = Session.Open_location

type startup = Cobalt_app.Controller.t

let open_project root =
  if Filename.is_relative root
  then Core.Or_error.error_string "Cobalt project root must be absolute"
  else
    match Cobalt_app.Startup.classify root with
    | File -> Core.Or_error.error_string "Cobalt project root must be an existing directory"
    | Directory -> Cobalt_app.Startup.open_path ~cell_width:Cobalt_screen.Cell_map.width root
;;

module Open_location = struct
  type position = Location.position = { line : int; column : int }

  type request = Location.request =
    { project_root : string
    ; relative_file : string
    ; position : position option
    }

  type buffer_id = Cobalt_app.Buffer_id.t

  let equal_buffer_id = Cobalt_app.Buffer_id.equal

  type failure = Location.failure =
    | Session_exited
    | Wrong_project of { expected : string; requested : string }
    | Invalid_relative_file of string
    | Target_unavailable of Core.Error.t
    | Invalid_position of Core.Error.t

  let to_error = Location.to_error
end

type t =
  { view : Bonsai_term.View.t
  ; cursor : Bonsai_term.Cursor.t option
  ; handle_event : Bonsai_term.Event.t -> unit Bonsai_term.Effect.t
  ; open_location :
      Open_location.request ->
      (Open_location.buffer_id, Open_location.failure) result Bonsai_term.Effect.t
  ; shutdown : unit -> unit Bonsai_term.Effect.t
  ; closed : bool
  }

let component ?set_clipboard ?on_toggle_terminal startup ~dimensions ~visible ~focused (local_ graph) =
  let hosted =
    Cobalt_ui.Editor_view.hosted ?set_clipboard ?on_toggle_terminal startup
      ~dimensions ~visible ~focused graph
  in
  let%arr { view; cursor; handle_event; open_location; shutdown; closed }
    : Cobalt_ui.Editor_view.hosted = hosted
  in
  let open_location request =
    Effect.map (open_location request) ~f:(function
      | Ok id -> Ok id
      | Error `Closed -> Error Open_location.Session_exited
      | Error (`Open failure) -> Error failure)
  in
  { view; cursor; handle_event; open_location; shutdown; closed }
;;
