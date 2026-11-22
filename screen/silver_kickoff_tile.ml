open! Core
open Cobalt_input
module Navigation = Cobalt_tile.Navigation
module Selection = Navigation.Selection

let id = Cobalt_tile.View_id.of_string "silver-kickoff"
let title = "Silver: Flow Runner"
let spec = Cobalt_tile.Spec.read_only id ~title
let review_id = Cobalt_tile.View_id.of_string "silver-kickoff-review"
let review_title = "Silver: Flow Review"
let review_spec = Cobalt_tile.Spec.read_only review_id ~title:review_title

let open_command_id = "silver-kickoff.focus"

let palette_entries ~installed ~review_installed =
  let create ~id ~title ?available ~priority_aliases action =
    Cobalt_palette.Catalog.Entry.create
      ~id ~title ~keywords:[ "companion"; "named flow" ]
      ?available ~priority_aliases
      (View action)
  in
  let command ~id ~title ~legacy action =
    create ~id ~title ~priority_aliases:[ title; legacy ] action
  in
  (* Keep the native destination in the catalog even without an adapter. Its exact
     alias is reserved and must not invoke a similarly named host or review command. *)
  create ~id:open_command_id ~title
    ~available:(fun context -> installed && Cobalt_core.Mode.equal context.mode Normal)
    ~priority_aliases:(if installed then [ "flow"; title; "Focus Silver flow kickoff" ] else [ "flow" ])
    (Show_view id)
  :: ((if installed
       then [ command ~id:"silver-kickoff.toggle" ~title:("Toggle " ^ title)
                ~legacy:"Toggle Silver flow kickoff" (Toggle_view id) ]
       else [])
      @ if review_installed
        then
          [ command ~id:"silver-kickoff.review" ~title:review_title
              ~legacy:"Review Silver flow kickoff" (Show_view review_id)
          ; command ~id:"silver-kickoff.toggle-review" ~title:("Toggle " ^ review_title)
              ~legacy:"Toggle Silver flow kickoff review" (Toggle_view review_id)
          ]
        else [])
;;

module Choice = struct
  type t = { id : string; label : string; catalog : int } [@@deriving sexp_of, equal]
end

module Target = struct
  type t =
    { id : string
    ; label : string
    ; catalog : int
    ; fields : (string * string) list
    }
  [@@deriving sexp_of, equal]
end

module Intent = struct
  type t =
    | Select of Choice.t
    | Apply of Target.t * (string * string) list
    | Prepare of int
    | Kickoff of int
  [@@deriving sexp_of, equal]
end

module Presentation = struct
  type t =
    { choices : Choice.t list
    ; selected : string option
    ; active : string option
    ; notice : string option
    ; targets : Target.t list
    ; draft : (int, string) result
    ; kickoff : (int, string) result
    ; details : string list
    }
  [@@deriving sexp_of, equal]

  let unavailable reason =
    { choices = []; selected = None; active = None; notice = Some reason
    ; targets = []; draft = Error reason; kickoff = Error reason; details = []
    }
  ;;
end

module Row = struct
  type t = Flow of int * string | Kickoff | Detail of int [@@deriving sexp_of, equal]
end

type t =
  { presentation : Presentation.t
  ; view : Row.t Selection.t
  ; intents : Intent.t list
  }
[@@deriving sexp_of]

let key = Type_equal.Id.create ~name:"silver-kickoff" sexp_of_t
let review_key = Type_equal.Id.create ~name:"silver-kickoff-review" sexp_of_t
let take_intents t = { t with intents = [] }, List.rev t.intents
let enqueue t intent = { t with intents = intent :: t.intents }

let target_row (target : Target.t) = Row.Flow (target.catalog, target.id)

let review_selection (presentation : Presentation.t) =
  let selected =
    List.find presentation.targets ~f:(fun target ->
      Option.equal String.equal presentation.selected (Some target.id))
    |> Option.map ~f:target_row
  in
  { Selection.empty with selected }
;;

let with_review_presentation t presentation =
  let generation (p : Presentation.t) =
    List.hd p.targets |> Option.map ~f:(fun target -> target.catalog)
  in
  if Presentation.equal t.presentation presentation then t
  else if Result.is_ok presentation.kickoff
          && not (Result.equal Int.equal String.equal t.presentation.kickoff presentation.kickoff)
  then { t with presentation; view = Selection.empty }
  else if not (Option.equal String.equal t.presentation.selected presentation.selected)
  then { t with presentation; view = review_selection presentation }
  else if Option.equal Int.equal (generation t.presentation) (generation presentation)
  then { t with presentation }
  else { t with presentation; view = review_selection presentation }
;;

let items t =
  let { Presentation.targets; kickoff; details; _ } = t.presentation in
  let kickoff =
    match kickoff with
    | Ok _ -> "Kickoff [K]: submit reviewed preview"
    | Error reason -> "Kickoff disabled: " ^ reason
  in
  let targets =
    List.map targets ~f:(fun target -> target_row target, "Flow choice: " ^ target.label)
  in
  let review = (Row.Kickoff, kickoff) :: List.mapi details ~f:(fun n text -> Row.Detail n, text) in
  match t.presentation.kickoff with
  | Ok _ -> review @ targets
  | Error _ -> targets @ review
;;

let ids t = List.map (items t) ~f:fst
let fit t ~rows = { t with view = Selection.fit t.view (ids t) ~equal:Row.equal ~rows }

type action =
  | Move of Navigation.Motion.t
  | Open
  | Apply of Target.t * (string * string) list
  | Prepare
  | Kickoff

let prepare = Key.char 'p'
let kickoff = Key.char 'K'

let interpret _ = function
  | [ Key.Enter ] -> Cobalt_tile.Content_key.Action Open
  | [ key ] when Key.equal key prepare -> Cobalt_tile.Content_key.Action Prepare
  | [ key ] when Key.equal key kickoff -> Cobalt_tile.Content_key.Action Kickoff
  | keys -> Cobalt_tile.Content_key.map (Navigation.interpret keys) ~f:(fun move -> Move move)
;;

let hint = "j/k: choose or scroll | Enter: edit/apply | p: preview | K: Kickoff | Esc"

let review_adapter : (t, action) View_registry.Adapter.t =
  { spec = review_spec
  ; key = review_key
  ; fit = (fun t _ ~rows ~width:_ -> fit t ~rows)
  ; leave = Fn.id
  ; text_view = (fun _ -> None)
  ; interpret
  ; escape = (fun _ -> None)
  ; hint
  ; perform = (fun t controller ~context:_ ~rows ~width:_ action ->
      let t = fit t ~rows in
      let done_ t = t, View_registry.Outcome.create controller in
      let notice text = t, View_registry.Outcome.create controller ~notice:(`Post text) in
      let kickoff () =
        match t.presentation.kickoff with
        | Ok reviewed -> done_ (enqueue t (Intent.Kickoff reviewed))
        | Error reason -> notice ("Kickoff disabled: " ^ reason)
      in
      match action with
      | Move motion ->
        done_ { t with view = Selection.move t.view (ids t) ~equal:Row.equal ~rows motion }
      | Prepare ->
        (match t.presentation.draft with
         | Ok draft -> done_ (enqueue t (Intent.Prepare draft))
         | Error reason -> notice ("Preview unavailable: " ^ reason))
      | Kickoff -> kickoff ()
      | Apply (target, fields) -> done_ (enqueue t (Intent.Apply (target, fields)))
      | Open ->
        (match t.view.selected with
         | Some Row.Kickoff -> notice "Use K to Kickoff the reviewed preview"
         | Some (Row.Flow _ as row) ->
           (match List.find t.presentation.targets ~f:(fun target ->
              Row.equal row (target_row target)) with
            | None -> notice "Silver flow catalog changed; select a flow again"
            | Some target when List.is_empty target.fields ->
              done_ (enqueue t (Intent.Apply (target, [])))
            | Some target ->
              let ask =
                View_registry.Ask.Form
                  { title = "Flow inputs · " ^ target.label
                  ; fields = target.fields
                  ; accept = (fun values -> Apply (target, values))
                  }
              in
              t, View_registry.Outcome.create controller ~ask)
         | Some (Row.Detail _) | None -> notice "Select a named flow to edit its inputs"))
  ; commands = (fun t ->
      let choose =
        if List.is_empty t.presentation.targets then []
        else [ Cobalt_tile.Local_command.create "inputs" ~keys:[ Enter ] "Edit or apply flow inputs" ]
      in
      (* The review key is direct: a generic palette command would capture only
         its command name and could outlive the preview the user saw. *)
      choose
      @ [ Cobalt_tile.Local_command.create "preview" ~keys:[ prepare ] "Prepare flow preview" ]
      @ Navigation.commands)
  ; signal = (fun _ _ -> None)
  ; label = (fun _ -> None)
  ; text_area = (fun _ ~rows:_ ~width:_ -> None)
  ; render = (fun t _ ~hotkey_hints ~focused ~notice ~pending ~width ~rows ->
      let view = (fit t ~rows).view in
      let top = if focused then view.top else 0 in
      let body =
        List.take (List.drop (items t) top) (Int.max 0 rows)
        |> List.map ~f:(fun (row, text) ->
          let selected = focused && Option.exists view.selected ~f:(Row.equal row) in
          Tile_text.row (if selected then Pending else Status)
            ((if selected then "› " else "  ") ^ text) ~width)
      in
      let default = if focused || hotkey_hints then hint else "" in
       { title = review_title; body; footer = Some (Tile_shell.Label.footer ~notice ~pending ~default) })
  }
;;

let review_entry presentation =
  View_registry.Entry.install ~opens_in:Tab review_adapter
    { presentation; view = review_selection presentation; intents = [] }
;;

let choices t = t.presentation.choices
let choice_row (choice : Choice.t) = Row.Flow (choice.catalog, choice.id)
let choice_ids t = List.map (choices t) ~f:choice_row

let with_presentation t presentation =
  if Presentation.equal t.presentation presentation then t
  else (
    let view =
      List.find presentation.choices ~f:(fun choice ->
        Option.equal String.equal (Some choice.id) presentation.selected)
      |> Option.value_map ~default:Selection.empty ~f:(fun choice ->
        { t.view with selected = Some (choice_row choice) })
    in
    { t with presentation; view })
;;

let fit_choices t ~rows =
  { t with view = Selection.fit t.view (choice_ids t) ~equal:Row.equal ~rows }
;;

let selector_hint = "j/k: select flow | Esc: editor"

let adapter : (t, Navigation.Motion.t) View_registry.Adapter.t =
  { spec
  ; key
  ; fit = (fun t _ ~rows ~width:_ -> fit_choices t ~rows)
  ; leave = Fn.id
  ; text_view = (fun _ -> None)
  ; interpret = (fun _ -> Navigation.interpret)
  ; escape = (fun _ -> None)
  ; hint = selector_hint
  ; perform = (fun t controller ~context:_ ~rows ~width:_ motion ->
      let view = Selection.move t.view (choice_ids t) ~equal:Row.equal ~rows motion in
      let choice =
        List.find (choices t) ~f:(fun choice ->
          Option.exists view.selected ~f:(Row.equal (choice_row choice)))
      in
      let t = { t with view } in
      let t = Option.value_map choice ~default:t ~f:(fun choice -> enqueue t (Select choice)) in
      t, View_registry.Outcome.create controller)
  ; commands = (fun _ -> Navigation.commands)
  ; signal = (fun _ _ -> None)
  ; label = (fun _ -> None)
  ; text_area = (fun _ ~rows:_ ~width:_ -> None)
  ; render = (fun t _ ~hotkey_hints ~focused ~notice ~pending ~width ~rows ->
      let view = (fit_choices t ~rows).view in
      let body =
        if List.is_empty (choices t) && rows > 0
        then
          [ Tile_text.row Status
              (Option.value t.presentation.notice ~default:"Silver advertises no named flows") ~width
          ]
        else
          List.take (List.drop (choices t) view.top) (Int.max 0 rows)
          |> List.map ~f:(fun choice ->
            let pointer = Option.exists view.selected ~f:(Row.equal (choice_row choice)) in
            let active = Option.equal String.equal t.presentation.active (Some choice.id) in
            let prefix = if pointer && (focused || active) then "› " else "  " in
            Tile_text.row (if active then Pending else Status)
              (prefix ^ choice.label ^ (if active then " · active" else "")) ~width)
      in
      let default =
        Option.value t.presentation.notice
          ~default:(if focused || hotkey_hints then selector_hint else "")
      in
      { title; body; footer = Some (Tile_shell.Label.footer ~notice ~pending ~default) })
  }
;;

let entry presentation =
  View_registry.Entry.install ~opens_in:Band adapter
    (with_presentation { presentation = Presentation.unavailable ""; view = Selection.empty; intents = [] } presentation)
;;
