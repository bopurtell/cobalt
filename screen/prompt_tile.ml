open! Core
open Cobalt_input
module Query = Cobalt_palette.Query

let id = Cobalt_tile.View_id.of_string "prompt"
let spec = Cobalt_tile.Spec.result_picker id ~title:"Prompt"

type t =
  { origin : Cobalt_tile.View_id.t
  ; title : string
  ; text : string
  ; validate : (string -> string option[@sexp.opaque])
  ; checked : bool (** Validation is shown: the text was edited, or Enter refused. *)
  ; form : ((string * string) list * int) option
  }
[@@deriving sexp_of]

let create ~origin ~title ~initial ~validate =
  { origin; title; text = Query.sanitize initial; validate; checked = false; form = None }
;;

let create_form ~origin ~title ~fields =
  let initial = List.hd fields |> Option.value_map ~default:"" ~f:snd in
  { (create ~origin ~title ~initial ~validate:(fun _ -> None)) with form = Some (fields, 0) }
;;

let origin t = t.origin
let is_form t = Option.is_some t.form
let title t = t.title
let text t = t.text
let error t = if t.checked then t.validate t.text else None
let preferred_size : Floating.Size.t = { width = 60; height = 4 }
let minimum : Floating.Size.t = { width = 20; height = 4 }

module Event = struct
  type t =
    | Insert of Uchar.t
    | Paste of string
    | Backspace
    | Delete_word
    | Clear
    | Field of int
  [@@deriving sexp_of]
end

type action =
  | Edit of Event.t
  | Accept
[@@deriving sexp_of]

let interpret t (keys : Key.t list) : action Cobalt_tile.Content_key.t =
  match keys with
  | [ Tab | Ctrl 'n' ] when Option.is_some t.form -> Action (Edit (Field 1))
  | [ Shift_tab | Ctrl 'p' ] when Option.is_some t.form -> Action (Edit (Field (-1)))
  | [ Ctrl 'u' ] when Option.is_some t.form -> Action (Edit Clear)
  | [ Char c ] -> Action (Edit (Insert c))
  | [ Backspace ] -> Action (Edit Backspace)
  | [ Ctrl ('w' | 'h') ] -> Action (Edit Delete_word)
  | [ Enter ] -> Action Accept
  | _ -> Unbound
;;

let hint t =
  if Option.is_some t.form then "Type a value, Tab/Shift-Tab changes field, Enter applies, Escape cancels"
  else "Type text; Ctrl-w deletes a word, Enter accepts, Escape cancels"
;;

let edited_fields t fields index =
  List.mapi fields ~f:(fun i (name, value) ->
    name, if i = index && not (String.equal (Query.sanitize value) t.text) then t.text else value)
;;

let update t (event : Event.t) =
  match event with
  | Field by ->
    (match t.form with
     | Some (fields, index) when not (List.is_empty fields) ->
       let fields = edited_fields t fields index in
       let index = (index + by + List.length fields) % List.length fields in
       { t with text = Query.sanitize (snd (List.nth_exn fields index)); form = Some (fields, index) }
     | _ -> t)
  | (Insert _ | Paste _ | Backspace | Delete_word | Clear) as event ->
    let text =
      match event with
      | Insert u -> Query.append t.text (Uchar.Utf8.to_string u)
      | Paste text -> Query.append t.text text
      | Backspace -> Query.backspace t.text
      | Delete_word -> Query.delete_word t.text
      | Clear -> ""
      | Field _ -> assert false
    in
    { t with text; checked = true }
;;

let accept t : (View_registry.Answer.t, t) Result.t =
  match t.form with
  | Some (fields, index) -> Ok (Fields (edited_fields t fields index))
  | None ->
    (match t.validate t.text with
     | None -> Ok (Text t.text)
     | Some _ -> Error { t with checked = true })
;;

let cursor t ~width = Picker_text.cursor t.text ~width

let render ?(hotkey_hints = false) ?notice t ~width ~rows : Tile_shell.Content.t =
  let input = Picker_text.query_row t.text ~width in
  let input = input @ [ Span.blank Status (Int.max 0 (width - Span.total_width input)) ] in
  let detail =
    Tile_text.row (Option.map (error t) ~f:(fun _ -> Style.Error) |> Option.value ~default:Status)
      (Option.value (error t) ~default:"") ~width
  in
  let detail =
    match t.form with
    | None -> detail
    | Some (fields, index) ->
      (match List.nth fields index with
       | None -> Tile_text.row Stale "No editable fields" ~width
       | Some (name, _) ->
         Tile_text.row Status (sprintf "%s (%d/%d)" name (index + 1) (List.length fields)) ~width)
  in
  let default =
    match t.form with
    | Some _ -> "Tab field | Enter apply | Esc cancel"
    | None -> if hotkey_hints then "Enter accept | Esc cancel" else ""
  in
  { title = t.title
  ; footer =
      Some
        (Tile_shell.Label.footer
           ~notice
           ~pending:None
           ~default)
  ; body = List.take [ input; detail ] (Int.max 0 rows)
  }
;;
