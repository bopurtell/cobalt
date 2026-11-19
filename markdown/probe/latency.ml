module Wall_clock = Unix

open! Core

module Provider = Cobalt_markdown.Provider
module Snapshot = Cobalt_decoration.Snapshot

let measure provider document name source =
  let key = Provider.key provider ~document ~revision:(Provider.parse_count provider) in
  let blocks = Provider.parse_count provider in
  let inlines = Provider.inline_parse_count provider in
  let wall_started = Wall_clock.gettimeofday () in
  let started = Stdlib.Sys.time () in
  let result = Provider.decorate provider ~key ~source in
  let elapsed_ms = (Stdlib.Sys.time () -. started) *. 1000. in
  let wall_ms = (Wall_clock.gettimeofday () -. wall_started) *. 1000. in
  let status =
    match result with
    | Ok snapshot -> sprintf "ok operations=%d" (List.length (Snapshot.operations snapshot))
    | Error error -> "error=" ^ Error.to_string_hum error
  in
  printf "%s bytes=%d wall_ms=%.3f cpu_ms=%.3f block_parses=%d inline_parses=%d %s\n%!"
    name (String.length source) wall_ms elapsed_ms
    (Provider.parse_count provider - blocks)
    (Provider.inline_parse_count provider - inlines) status
;;

let () =
  let provider = Provider.create () in
  let document = Snapshot.Document_id.create () in
  Exn.protect
    ~finally:(fun () -> Provider.close provider)
    ~f:(fun () ->
      let representative =
        "# Markdown latency\n\n"
        ^ String.concat
            (List.init 80 ~f:(fun i ->
               sprintf "- [ ] item %d **strong** and *emphasis* with [label](https://example.test).\n" i))
      in
      measure provider document "representative-cold" representative;
      measure provider document "representative-warm" representative;
      measure provider document "multiline-quote" "> *first\n> continuation* and `code`\n";
      measure provider document "fenced-only" "```ocaml\n**raw**\n```\n";
      measure provider document "invalid-utf8" "\xff";
      measure provider document "over-byte-limit" (String.make (256 * 1024 + 1) 'x');
      measure provider document "operation-limit"
        (String.concat (List.init 4097 ~f:(fun _ -> "*a* ")));
      measure provider document "inline-call-limit"
        ("| a | b |\n| --- | --- |\n"
         ^ String.concat (List.init 2048 ~f:(fun _ -> "| a | b |\n")));
      let delimiters = String.make 2200 '*' in
      measure provider document "deep-inline-nesting" (delimiters ^ "x" ^ delimiters ^ "\n");
      measure provider document "deep-blockquote"
        (String.concat (List.init 1100 ~f:(fun _ -> "> ")) ^ "x\n"))
;;
