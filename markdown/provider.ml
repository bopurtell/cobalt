open! Core

module Snapshot = Cobalt_decoration.Snapshot

type t =
  { mutable native : Native.t option
  ; mutable closed : bool
  }

let create () = { native = None; closed = false }

let close t =
  if not t.closed
  then (
    t.closed <- true;
    Option.iter t.native ~f:Native.close)
;;

let configuration = "source-style-v1:markdown-41ff24a6:256k:4096lines:4096ops:100ms"
let provider = "cobalt-markdown-v1"

let key _t ~document ~revision =
  Snapshot.Key.create ~document ~revision ~provider ~configuration
;;

let parse_count t =
  match t.native with
  | None -> 0
  | Some native -> fst (Native.counts native)
;;

let inline_parse_count t =
  match t.native with
  | None -> 0
  | Some native -> snd (Native.counts native)
;;

let eligible_path = function
  | None -> false
  | Some path ->
    let path = String.lowercase path in
    String.is_suffix path ~suffix:".md"
    || String.is_suffix path ~suffix:".markdown"
;;

let limits =
  { Snapshot.Limits.max_source_bytes = 256 * 1024
  ; max_operations = 4096
  ; max_replacement_bytes = 0
  ; max_total_replacement_bytes = 0
  }
;;

(* These tags are feature-local, not the representation of Snapshot.Role.t. *)
let role = function
  | 1 -> Snapshot.Role.Heading_1
  | 2 -> Heading_2
  | 3 -> Heading_3
  | 4 -> Heading_4
  | 5 -> Heading_5
  | 6 -> Heading_6
  | 7 -> Emphasis
  | 8 -> Strong
  | 9 -> Code_inline
  | 10 -> Code_block
  | 11 -> Link
  | 12 -> Link_destination
  | 13 -> Quote
  | 14 -> List_marker
  | 15 -> Checkbox
  | _ -> failwith "unexpected native Markdown style tag"
;;

let error message = Error (Error.of_string ("Markdown: " ^ message))

let decorate t ~key ~source =
  if t.closed
  then error "provider is closed"
  else if not (String.equal (Snapshot.Key.provider key) provider)
          || not (String.equal (Snapshot.Key.configuration key) configuration)
  then error "provider/configuration key mismatch"
  else if String.length source > limits.max_source_bytes
  then error "source byte limit exceeded"
  else if String.count source ~f:(Char.equal '\n') >= 4096
  then error "line limit exceeded"
  else (
    (* Snapshot validates UTF-8 before even lazily allocating native parsers.
       Validation is repeated for native output so no malformed range escapes. *)
    match Snapshot.create ~limits ~key ~source [] with
    | Error _ as error -> error
    | Ok _ ->
      (try
         let native =
           match t.native with
           | Some native -> native
           | None ->
             let native = Native.create () in
             t.native <- Some native;
             native
         in
         let operations =
           Native.parse native source
           |> Array.to_list
           |> List.map ~f:(fun (tag, start, stop) ->
             Snapshot.Operation.Style
               { range = { start; stop }; role = role tag })
         in
         Snapshot.create ~limits ~key ~source operations
       with
       | Failure message -> error message
       | Invalid_argument message -> error message))
;;
