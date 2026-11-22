(* Opt-in smoke test of the production pool against Cargo and rust-analyzer. *)
open! Core
open! Async
module Source = Cobalt_source.Source
module Lsp = Cobalt_source.Lsp_client
module Query = Cobalt_error.Language_query
module Event = Cobalt_error.Source_event

let await source description find =
  let rec loop () =
    let%bind events = Source.next_batch source in
    List.iter events ~f:(function
      | Event.Stopped { reason; _ } | Unavailable { reason; _ } -> failwith reason
      | _ -> ());
    match List.find_map events ~f:find with
    | Some x -> return x
    | None -> loop ()
  in
  match%map Clock_ns.with_timeout (Time_ns.Span.of_int_sec 60) (loop ()) with
  | `Timeout -> failwith ("timed out: " ^ description)
  | `Result result -> result
;;

let write root path contents =
  let file = Filename.concat root path in
  Core_unix.mkdir_p (Filename.dirname file);
  Writer.save file ~contents
;;

let package name =
  sprintf "[package]\nname = %S\nversion = \"0.1.0\"\nedition = \"2021\"\n" name
;;

let symbol = "pub fn cobalt_answer() -> u32 { 42 }\n"

let check root ~entry ~target ~qualifier =
  let source = Lsp.start_workspace ~cell_width:Cobalt_screen.Cell_map.width () in
  Monitor.protect (fun () ->
    let resource = Filename.concat root entry in
    let dependency = if String.equal qualifier "api" then "mod api;\n" else "" in
    let text annotation ident =
      sprintf "%sfn main() { let _: %s = %s::%s(); }\n" dependency annotation qualifier ident
    in
    let broken = text "bool" "cobalt_answer" in
    let fixed = text "u32" "cobalt_answer" in
    let find_error = function
      | Event.Owned { resource = r; generation = 1; event = Diagnostics d } when String.equal r resource ->
        Some (List.exists d.findings ~f:(fun f ->
          String.is_substring f.message ~substring:"mismatched types"
          || (String.is_substring f.message ~substring:"bool"
              && String.is_substring f.message ~substring:"u32")))
      | _ -> None
    in
    let send = Source.send source in
    let%bind () = write root entry broken in
    send (Document_opened { resource; generation = 1 });
    send (Document_changed { resource; text = broken; revision = 0 });
    let%bind () = await source "type error" (fun event ->
      match find_error event with Some true -> Some () | _ -> None) in
    send Inspect;
    let%bind () = await source "workspace root" (function
      | Servers [ { status = Running; root = actual; resources = [ file ]; _ } ] ->
        if not (String.equal root actual && String.equal file resource)
        then failwith (sprintf "wrong workspace root: %s (wanted %s)" actual root);
        Some ()
      | _ -> None) in
    (* rust-analyzer's Cargo diagnostic pass reads disk on save. Check that save
       clears the same error, then exercise intelligence on the live buffer. *)
    let%bind () = Writer.save resource ~contents:fixed in
    send (Document_changed { resource; text = fixed; revision = 1 });
    send (Document_saved { resource; revision = 1 });
    let%bind () = await source "diagnostic clear" (fun event ->
      match find_error event with Some false -> Some () | _ -> None) in
    let token revision request : Cobalt_completion.Model.Token.t =
      { resource; generation = 1; revision; request }
    in
    let cursor = String.substr_index_exn fixed ~pattern:"cobalt_answer" + 2 in
    let query request kind =
      let token = token 1 request in
      send (Query { token; cursor; kind });
      await source "language query" (function
        | Query_result reply when Cobalt_completion.Model.Token.equal token reply.token -> Some reply.result
        | _ -> None)
    in
    let%bind hover = query 1 Query.Hover in
    (match hover with
     | Hover_result (Some { contents; _ }) when List.exists contents ~f:(fun c ->
         String.is_substring c.value ~substring:"cobalt_answer") -> ()
     | _ -> failwith (sprintf "wrong hover: %s" (Sexp.to_string ([%sexp_of: Query.result] hover))));
    let%bind location = query 2 Query.Definition in
    (match location with
     | Locations targets when List.exists targets ~f:(fun loc ->
         String.equal loc.path (Filename.concat root target)
         && loc.selection.start.line = 0 && loc.selection.start.character = 7) -> ()
     | _ -> failwith (sprintf "wrong definition: %s" (Sexp.to_string ([%sexp_of: Query.result] location))));
    let text = text "u32" "cobalt_answ" in
    let fallback_start = String.substr_index_exn text ~pattern:"cobalt_answ" in
    let cursor = fallback_start + String.length "cobalt_answ" in
    let token = token 2 3 in
    send (Document_changed { resource; text; revision = 2 });
    send (Complete { token; cursor; fallback_start; fallback_stop = cursor; trigger = Automatic });
    let%map () = await source "completion" (function
      | Completion reply when Cobalt_completion.Model.Token.equal token reply.token ->
        if not (List.exists reply.candidates ~f:(fun c ->
          c.primary.start = fallback_start && c.primary.stop = cursor
          && String.is_prefix c.primary.text ~prefix:"cobalt_answer"))
        then failwith ("missing completion: " ^ Sexp.to_string ([%sexp_of: Cobalt_completion.Model.Reply.t] reply));
        Some ()
      | _ -> None) in
    printf "%s: workspace root, diagnostics/clear, hover, definition -> %s, and completion OK\n%!"
      entry target)
    ~finally:(fun () -> Source.stop source; return ())
;;

let main () =
  let temp = Filename_unix.realpath (Filename_unix.temp_dir "cobalt-rust-lsp" "") in
  let standalone = Filename.concat temp "standalone" in
  let workspace = Filename.concat temp "workspace" in
  Monitor.protect (fun () ->
    let%bind () = write standalone "Cargo.toml" (package "standalone") in
    let%bind () = write standalone "src/api.rs" symbol in
    let%bind () = check standalone ~entry:"src/main.rs" ~target:"src/api.rs" ~qualifier:"api" in
    let%bind () = write workspace "Cargo.toml" "[workspace]\nmembers = [\"app\", \"shared\"]\nresolver = \"2\"\n" in
    let%bind () = write workspace "app/Cargo.toml"
      (package "app" ^ "[dependencies]\nshared = { path = \"../shared\" }\n") in
    let%bind () = write workspace "shared/Cargo.toml" (package "shared") in
    let%bind () = write workspace "shared/src/lib.rs" symbol in
    check workspace ~entry:"app/src/main.rs" ~target:"shared/src/lib.rs" ~qualifier:"shared")
    ~finally:(fun () ->
      let%bind () = Clock_ns.after (Time_ns.Span.of_int_ms 1100) in
      Process.run_exn ~prog:"/bin/rm" ~args:[ "-rf"; temp ] () >>| ignore)
;;

let () = Command.async ~summary:"Smoke-test real rust-analyzer in standalone and workspace Cargo projects"
    (Command.Param.return main)
  |> Command_unix.run
;;
