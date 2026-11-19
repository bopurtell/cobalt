open! Core
open Cobalt_core
open Cobalt_app
open Cobalt_screen

module Snapshot = Cobalt_decoration.Snapshot

module Session = struct
  type t =
    { key : document:Snapshot.Document_id.t -> revision:int -> Snapshot.Key.t
    ; decorate : key:Snapshot.Key.t -> source:string -> Snapshot.t Or_error.t
    ; close : unit -> unit
    }
end

module Factory = struct
  type t =
    { available : bool
    ; eligible_path : string option -> bool
    ; create : unit -> Session.t
    }

  let unavailable =
    { available = false; eligible_path = (fun _ -> false)
    ; create = (fun () -> failwith "Document decorations unavailable") }
  ;;
end

type source =
  { owner : Buffer_id.t
  ; identity : Controller.Document_id.t
  ; text : Text_buffer.t
  ; revision : int
  ; path : string option
  }

type active =
  { owner : Buffer_id.t
  ; identity : Controller.Document_id.t
  ; path : string option
  ; document : Snapshot.Document_id.t
  ; mutable session : Session.t option
  ; mutable attempted : (source * Snapshot.Key.t option) option
  ; mutable published : (source * Snapshot.Key.t * Decoration.t) option
  }

type t =
  { factory : Factory.t
  ; mutable active : active option
  ; mutable unavailable_notified : bool
  }

let create factory = { factory; active = None; unavailable_notified = false }

(* Only documented recoverable callback failures become notices. In particular,
   never turn allocation/stack exhaustion, interrupts, or unrelated editor bugs
   into an ordinary optional-feature failure. Call this around callbacks only. *)
let provider_call f =
  try Ok (f ()) with
  | (Failure _ | Invalid_argument _) as exn -> Or_error.of_exn exn
;;

let close_session active =
  let session = active.session in
  active.session <- None;
  Option.iter session ~f:(fun session ->
    (* Recoverable cleanup failures must not prevent baseline editing. Fatal or
       unexpected exceptions still propagate, just as at every other boundary. *)
    ignore (provider_call session.close : unit Or_error.t))
;;

let clear t =
  Option.iter t.active ~f:close_session;
  t.active <- None
;;

let source ui ~width ~height =
  (* Mirror Frame.prepare's surface selection, not the session's retained hidden
     file. A focused sidebar can show a file, a major directory cannot. *)
  let ui = if Option.is_some (Ui_state.side_layout ui ~width ~height)
    then Ui_state.surface ui ~directory:false else ui in
  let hidden_by_tab = Option.exists (Ui_state.active_tab_view ui) ~f:(fun id ->
    Option.is_some (Ui_state.minor_layout ui ~width ~height id)) in
  let session = Ui_state.session ui in
  if hidden_by_tab then None else
  Option.bind (Cobalt_app.Session.active_id session) ~f:(fun owner ->
    let controller = Ui_state.controller ui in
      match Controller.kind controller with
      | Directory -> None
      | File ->
        let editor = Controller.editor controller in
        Some { owner; identity = Controller.document_id controller
             ; text = Editor.text editor; revision = Editor.revision editor
             ; path = Editor.path editor })
;;

let same_source (a : source) (b : source) =
  Buffer_id.equal a.owner b.owner && Controller.Document_id.equal a.identity b.identity
  && phys_equal a.text b.text
  && a.revision = b.revision && Option.equal String.equal a.path b.path
;;

let enabled t ui = t.factory.available && Ui_state.document_decorations_enabled ui
  && not (Ui_state.exited ui)
;;

let within_budget source =
  Text_buffer.length source.text <= 256 * 1024
  && Text_buffer.line_count source.text <= 4096
;;

let decorations ?(width = 80) ?(height = 24) t ui =
  if not (enabled t ui) then None
  else Option.bind t.active ~f:(fun active ->
    Option.bind active.published ~f:(fun (published_source, key, prepared) ->
      Option.bind (source ui ~width ~height) ~f:(fun current ->
        if same_source published_source current then Some (key, prepared) else None)))
;;

let follow ?(parse = true) ?(width = 80) ?(height = 24) t ui =
  let ui = Ui_state.with_document_decorations ui ~available:t.factory.available in
  if not t.factory.available && Ui_state.document_decorations_enabled ui
     && not t.unavailable_notified && not (Ui_state.exited ui)
  then (
    t.unavailable_notified <- true;
    clear t;
    Ui_state.with_notice ~source:"document decorations" ui
      "Document decorations unavailable in this build")
  else if not (enabled t ui) then (clear t; ui)
  else
    match source ui ~width ~height with
    | None -> clear t; ui
    | Some current when not (t.factory.eligible_path current.path)
                        || not (within_budget current) ->
      clear t; ui
    | Some current ->
      let active =
        match t.active with
        | Some active when Buffer_id.equal active.owner current.owner
                           && Controller.Document_id.equal active.identity current.identity
                           && Option.equal String.equal active.path current.path -> active
        | _ ->
          clear t;
          let active =
            { owner = current.owner; identity = current.identity; path = current.path
            ; document = Snapshot.Document_id.create (); session = None
            ; attempted = None; published = None } in
          t.active <- Some active;
          active
      in
      (match active.published with
       | Some (previous, _, _) when not (same_source previous current) ->
         active.published <- None
       | _ -> ());
      if not parse then ui
      else
        let failed_same_source =
          Option.is_none active.session
          && Option.exists active.attempted ~f:(fun (previous, _) ->
            same_source previous current) in
        if failed_same_source then ui
        else
          let key = ref None in
          let result =
            let open Or_error.Let_syntax in
            let%bind session = match active.session with
              | Some session -> Ok session
              | None ->
                let%map session = provider_call t.factory.create in
                active.session <- Some session;
                session in
            let%bind expected = provider_call (fun () ->
              session.key ~document:active.document ~revision:current.revision) in
            key := Some expected;
            let already_attempted = Option.exists active.attempted
              ~f:(fun (previous, previous_key) ->
                same_source previous current
                && Option.equal Snapshot.Key.equal previous_key (Some expected)) in
            if already_attempted then Ok ()
            else (
              active.published <- None;
              active.attempted <- Some (current, Some expected);
              let source_text = Text_buffer.to_string current.text in
              let%bind snapshot = provider_call (fun () ->
                session.decorate ~key:expected ~source:source_text) |> Or_error.join in
              let%bind () = if Snapshot.matches snapshot expected then Ok ()
                else Or_error.error_string "Provider returned a stale decoration key" in
              let%bind prepared = Decoration.prepare ~source:current.text snapshot in
              (* Bounded synchronous work: no yield between capture/publication. *)
              let%map current_key = provider_call (fun () ->
                session.key ~document:active.document ~revision:current.revision) in
              let fresh = Option.exists (source ui ~width ~height) ~f:(same_source current)
                && enabled t ui
                && Snapshot.Key.equal expected current_key in
              if fresh then active.published <- Some (current, expected, prepared))
          in
          match result with
          | Ok () -> ui
          | Error error ->
            active.attempted <- Some (current, !key);
            active.published <- None;
            close_session active;
            Ui_state.with_notice ~source:"document decorations" ui
              ("Document decorations failed: " ^ String.prefix (Error.to_string_hum error) 240)
;;
