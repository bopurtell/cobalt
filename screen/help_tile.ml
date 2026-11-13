open! Core
module Local_command = Cobalt_tile.Local_command
module Navigation = Cobalt_tile.Navigation

let id = Cobalt_tile.View_id.of_string "help"
let spec = Cobalt_tile.Spec.read_only id ~title:"Help"

type t =
  { origin : Cobalt_tile.View_id.t
  ; title : string
  ; commands : Local_command.t list
  ; rows : (string * string) list (** Keys as shown, and descriptions. *)
  ; top : int
  }
[@@deriving sexp_of]

let create ~origin ~title commands =
  { origin
  ; title
  ; commands
  ; rows =
      List.map commands ~f:(fun (command : Local_command.t) ->
        Local_command.keys_hum command, command.description)
  ; top = 0
  }
;;

let of_entries ~origin ~title rows = { origin; title; commands = []; rows; top = 0 }
let origin t = t.origin
let commands t = t.commands
let top t = t.top

let keys_width t =
  List.fold t.rows ~init:0 ~f:(fun width (keys, _) -> Int.max width (String.length keys))
;;

let preferred_size t : Floating.Size.t =
  let widest =
    List.fold t.rows ~init:0 ~f:(fun width (_, description) ->
      Int.max width (String.length description))
  in
  (* Frame, padding, the key column and its gap, and the description. *)
  { width = Int.max 32 (keys_width t + widest + 6); height = List.length t.rows + 2 }
;;

type action =
  | Scroll of Navigation.Motion.t
  | Close
[@@deriving sexp_of]

let interpret (keys : Cobalt_input.Key.t list) : action Cobalt_tile.Content_key.t =
  match keys with
  | [ key ]
    when Cobalt_input.Key.equal key (Cobalt_input.Key.char 'q')
         || Cobalt_input.Key.equal key (Cobalt_input.Key.char '?') -> Action Close
  | keys -> Cobalt_tile.Content_key.map (Navigation.interpret keys) ~f:(fun m -> Scroll m)
;;

let hint = "Read-only help: j/k scroll; q, ? or Escape closes"

let scroll t ~rows motion =
  { t with
    top = Navigation.move_offset t.top ~total:(List.length t.rows) ~rows motion
  }
;;

let render ?(hotkey_hints = false) ?notice t ~width ~rows : Tile_shell.Content.t =
  let rows = Int.max 0 rows in
  let count = List.length t.rows in
  let top = Int.clamp_exn t.top ~min:0 ~max:(Int.max 0 (count - rows)) in
  let column = keys_width t in
  let body =
    if count = 0
    then List.take [ Tile_text.row Stale "No view-local commands" ~width ] rows
    else
      List.take (List.drop t.rows top) rows
      |> List.map ~f:(fun (keys, description) ->
        Tile_text.row Status (sprintf "%-*s  %s" column keys description) ~width)
  in
  { title = sprintf "%s keys" t.title
  ; footer =
      Some
        (Tile_shell.Label.footer
           ~notice
           ~pending:None
           ~default:
             (sprintf
                "%d above, %d below%s"
                top
                (Int.max 0 (count - top - rows))
                (if hotkey_hints then " | j/k q Esc" else "")))
  ; body
  }
;;
