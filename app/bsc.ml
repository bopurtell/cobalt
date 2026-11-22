open! Core
module Feedback = Cobalt_error.Error

type action = Check | Build [@@deriving sexp_of, equal]
type request = { id : int; action : action; directory : string; dirty : string list }
type command = { program : string; args : string list }

type result =
  { root : string
  ; findings : (string * Feedback.Diagnostics.Finding.t) list
  ; success : bool
  ; status : string
  }

let config_name = ".cobalt-bsc"
let action_name = function Check -> "check" | Build -> "build"
let source_prefix = "BSC run #"
let source id = source_prefix ^ Int.to_string id
let is_source = String.is_prefix ~prefix:source_prefix
let classic path = String.is_suffix path ~suffix:".bs"

let command action text =
  Or_error.try_with (fun () ->
    let entries =
      match Sexp.of_string text with
      | List entries -> entries
      | Atom _ -> failwith "Expected ((check (program arg ...)) (build (program arg ...)))"
    in
    let commands = List.map entries ~f:(function
      | Sexp.List [ Atom ("check" | "build" as name); List argv ] ->
        let atom = function
          | Sexp.Atom text when not (String.contains text '\000') -> text
          | _ -> failwith "Each command argument must be a string without NUL"
        in
        (match List.map argv ~f:atom with
         | program :: args when not (String.is_empty program) -> name, { program; args }
         | _ -> failwith (sprintf "The %s program must not be empty" name))
      | _ -> failwith "Expected (check (program arg ...)) or (build (program arg ...))")
    in
    let commands = match String.Map.of_alist commands with
      | `Ok commands -> commands
      | `Duplicate_key name -> failwith (sprintf "Duplicate %s command" name)
    in
    let name = action_name action in
    Option.value_or_thunk (Map.find commands name)
      ~default:(fun () -> failwith (sprintf "No %s command configured" name)))
;;

(* BSC prints paths using Haskell's [show], not shell quoting. *)
let quoted input =
  let length = String.length input in
  if length = 0 || not (Char.equal input.[0] '"') then None else
  let b = Buffer.create 64 in
  let rec loop i =
    if i >= length then None else
    match input.[i] with
    | '"' -> Some (Buffer.contents b, String.drop_prefix input (i + 1))
    | '\\' when i + 1 < length ->
      (match input.[i + 1] with
       | ('\\' | '"') as c -> Buffer.add_char b c; loop (i + 2)
       | '&' -> loop (i + 2)
       | 't' -> Buffer.add_char b '\t'; loop (i + 2)
       | 'n' -> Buffer.add_char b '\n'; loop (i + 2)
       | c when Char.is_digit c ->
         let stop = ref (i + 2) in
         while !stop < length && Char.is_digit input.[!stop] do Int.incr stop done;
         (match Int.of_string_opt (String.sub input ~pos:(i + 1) ~len:(!stop - i - 1)) with
          | Some scalar when Stdlib.Uchar.is_valid scalar ->
            Stdlib.Buffer.add_utf_8_uchar b (Stdlib.Uchar.of_int scalar);
            loop !stop
          | _ -> None)
       | _ -> None)
    | c -> Buffer.add_char b c; loop (i + 1)
  in
  loop 1
;;

let location text =
  let open Option.Let_syntax in
  let%bind file, rest = quoted text in
  let%bind rest = String.chop_prefix rest ~prefix:", line " in
  let%bind position, message = String.lsplit2 rest ~on:':' in
  let line, column =
    match String.substr_index position ~pattern:", column " with
    | None -> position, if classic file then "0" else "1"
    | Some i -> String.prefix position i, String.drop_prefix position (i + 9)
  in
  let%bind line = Int.of_string_opt (String.strip line) in
  let%bind column = Int.of_string_opt (String.strip column) in
  if String.is_empty file || line <= 0 || column < (if classic file then 0 else 1) then None
  else Some (file, { Feedback.Problem.Location.line; column }, String.strip message)
;;

let findings ~root output =
  let config = Filename.concat root config_name in
  let header line =
    List.find_map
      [ "Error: ", Feedback.Severity.Error; "Warning: ", Warning; "Message: ", Info ]
      ~f:(fun (prefix, severity) ->
        Option.map (String.chop_prefix line ~prefix) ~f:(fun rest ->
          match location rest with
          | Some (file, position, message) ->
            let file = Cobalt_core.Resource.normalize ~cwd:root file in
            file, severity, Some position, [ message ]
          | None -> config, severity, None, [ String.strip rest ]))
  in
  let finish pending acc =
    Option.value_map pending ~default:acc ~f:(fun (file, severity, location, lines) ->
      let message = String.concat ~sep:" " (List.rev lines |> List.filter ~f:(Fn.non String.is_empty)) in
      (file, { Feedback.Diagnostics.Finding.severity; message; location }) :: acc)
  in
  let acc, pending = List.fold (String.split_lines output) ~init:([], None)
    ~f:(fun (acc, pending) line ->
      match header line with
      | Some h -> finish pending acc, Some h
      | None when String.is_empty (String.strip line) ||
          (not (String.is_empty line) && Char.is_whitespace line.[0]) ->
        acc, Option.map pending ~f:(fun (file, severity, location, lines) ->
          file, severity, location, String.strip line :: lines)
      | None -> finish pending acc, None) in
  List.rev (finish pending acc)
;;

let offset ~path text ~line ~column =
  let module Text = Cobalt_core.Text_buffer in
  let origin = if classic path then 0 else 1 in
  if line < 1 || line > Text.line_count text || column < origin
  then Or_error.error_string "BSC location is outside the document"
  else
    let start = Text.line_start text (line - 1) in
    let contents = Text.line_text text (line - 1) in
    let rec loop byte col =
      if col >= column then Ok (start + byte)
      else if byte >= String.length contents then Or_error.error_string "BSC column is outside the line"
      else
        let len = Stdlib.Uchar.utf_decode_length (Stdlib.String.get_utf_8_uchar contents byte) in
        let next = if Char.equal contents.[byte] '\t' then col + 8 - ((col - origin) mod 8) else col + 1 in
        if next > column then Ok (start + byte) else loop (byte + len) next
    in
    loop 0 origin
;;
