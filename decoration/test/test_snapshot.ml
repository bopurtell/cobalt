open! Core
open Cobalt_decoration

let key ?(document = Snapshot.Document_id.create ()) ?(revision = 0)
    ?(provider = "synthetic-v1") ?(configuration = "default") () =
  Snapshot.Key.create ~document ~revision ~provider ~configuration
;;

let range start stop = { Snapshot.Range.start; stop }
let style start stop role = Snapshot.Operation.Style { range = range start stop; role }
let replace ?role start stop text =
  Snapshot.Operation.Replace { range = range start stop; text; role }
;;
let create ?limits source operations =
  Snapshot.create ?limits ~key:(key ()) ~source operations
;;
let snapshot ?limits source operations = create ?limits source operations |> Or_error.ok_exn
let rejects ?limits source operations = assert (Result.is_error (create ?limits source operations))

let document_roles : Snapshot.Role.t list =
  [ Accent; Literal; Muted
  ; Heading_1; Heading_2; Heading_3; Heading_4; Heading_5; Heading_6
  ; Emphasis; Strong; Code_inline; Code_block; Link; Link_destination
  ; Quote; List_marker; Checkbox ]
;;

let%test_unit "generic document roles have stable declaration-order precedence" =
  List.iteri document_roles ~f:(fun i role ->
    let earlier = List.take document_roles i in
    List.iter earlier ~f:(fun before ->
      assert (Snapshot.Role.compare before role < 0);
      List.iter [ [ style 0 3 role; style 0 3 before ]
                ; [ style 0 3 before; style 0 3 role ] ] ~f:(fun operations ->
        let s = snapshot "abc" operations in
        [%test_result: Snapshot.Role.t option] (Snapshot.style_at s 1)
          ~expect:(Some before)));
    let s = snapshot "abcde" [ style 0 5 Accent; style 1 4 role ] in
    let lookup = Snapshot.lookup_from s 0 in
    List.iter [ 0, Some Snapshot.Role.Accent; 1, Some role; 3, Some role
              ; 4, Some Accent; 5, None; 1, Some role ] ~f:(fun (at, expected) ->
      [%test_result: Snapshot.Role.t option] (lookup at) ~expect:expected))
;;

let%test_unit "empty snapshot and source provenance" =
  let s = snapshot "" [] in
  assert (Snapshot.is_empty s);
  [%test_result: int] (Snapshot.source_length s) ~expect:0;
  [%test_result: Snapshot.Operation.t list] (Snapshot.operations s) ~expect:[];
  [%test_result: Snapshot.Role.t option] (Snapshot.style_at s 0) ~expect:None;
  let source = "é\n界x" in
  let operations = [ replace ~role:Accent 3 6 "•"; style 0 7 Muted ] in
  let s = snapshot source operations in
  assert (not (Snapshot.is_empty s));
  [%test_result: int] (Snapshot.source_length s) ~expect:7;
  [%test_result: Snapshot.Operation.t list] (Snapshot.operations s)
    ~expect:[ style 0 7 Muted; replace ~role:Accent 3 6 "•" ];
  [%test_result: string] source ~expect:"é\n界x";
  (* The model is width-independent; the renderer must reject these if unsafe. *)
  ignore (snapshot "x" [ replace 0 1 ""; style 0 1 Literal ] : Snapshot.t);
  ignore (snapshot "x" [ replace 0 1 "界界" ] : Snapshot.t);
  ignore (snapshot "\t" [ replace 0 1 "x" ] : Snapshot.t)
;;

let%test_unit "freshness includes document, revision, provider and configuration" =
  let document = Snapshot.Document_id.create () in
  let current = key ~document () in
  let s = Snapshot.create ~key:current ~source:"abc" [ style 0 3 Accent ] |> Or_error.ok_exn in
  assert (Snapshot.Key.equal (Snapshot.key s) current);
  assert (Snapshot.matches s (key ~document ()));
  [%test_result: int] (Snapshot.Key.revision current) ~expect:0;
  [%test_result: string] (Snapshot.Key.provider current) ~expect:"synthetic-v1";
  [%test_result: string] (Snapshot.Key.configuration current) ~expect:"default";
  List.iter
    [ key (); key ~document ~revision:1 (); key ~document ~provider:"synthetic-v2" ()
    ; key ~document ~configuration:"reconfigured" ()
    ]
    ~f:(fun k -> assert (not (Snapshot.matches s k)));
  assert (Snapshot.Key.same_document current (key ~document ~revision:2 ()));
  assert (not (Snapshot.Key.same_document current (key ())))
;;

let%test_unit "atomic invalid ranges, including extreme integers and UTF-8 boundaries" =
  let source = "é\n界x" in
  List.iter
    [ -1, 2; 0, 0; 4, 4; 6, 3; 0, 8; 8, 9; 1, 2; 3, 5
    ; Int.min_value, Int.max_value; 0, Int.max_value
    ]
    ~f:(fun (start, stop) ->
      rejects source [ style 0 2 Muted; style start stop Accent ];
      rejects source [ style 0 2 Muted; replace start stop "x" ]);
  rejects "" [ style 0 0 Accent ];
  ignore (snapshot source [ style 0 7 Accent; replace 0 2 "e"; replace 3 6 "x" ]
          : Snapshot.t)
;;

let%test_unit "invalid UTF-8 rejected, including overlong, surrogate and truncated sequences" =
  let invalid =
    [ "\255"; "\128"; "\192\175"; "\224\128\128"; "\237\160\128"
    ; "\244\144\128\128"; "\245\128\128\128"; "\226\130"; "\240\159\146"
    ]
  in
  List.iter invalid ~f:(fun text ->
    rejects text [];
    rejects "ab" [ style 0 1 Accent; replace 1 2 text ]);
  ignore (snapshot "aé界😀" [ replace 0 1 "é界😀" ] : Snapshot.t)
;;

let%test_unit "replacement source is one LF-delimited line; controls never reach display" =
  List.iter [ 0, 2; 1, 2; 1, 3; 0, 3 ] ~f:(fun (start, stop) ->
    rejects "a\nb" [ replace start stop "x" ]);
  ignore (snapshot "a\nb" [ replace 0 1 "x"; replace 2 3 "y"; style 0 3 Muted ]
          : Snapshot.t);
  for byte = 0 to 31 do
    rejects "a" [ replace 0 1 (String.of_char (Char.of_int_exn byte)) ]
  done;
  rejects "a" [ replace 0 1 "\127" ];
  for byte = 128 to 159 do
    rejects "a" [ replace 0 1 ("\194" ^ String.of_char (Char.of_int_exn byte)) ]
  done;
  List.iter [ "\t"; "\r"; "\n"; "\027[31m"; "x\nx"; "x\000x" ] ~f:(fun text ->
    rejects "abc" [ replace 0 1 text ]);
  (* Combining and width context deliberately belong to the Cell_map adapter. *)
  ignore (snapshot "a" [ replace 0 1 "\204\129" ] : Snapshot.t)
;;

let%test_unit "all replacement overlap forms rejected, adjacency accepted" =
  List.iter
    [ replace 1 4 "x", replace 2 3 "y"
    ; replace 1 3 "x", replace 2 4 "y"
    ; replace 1 3 "x", replace 1 3 "x"
    ; replace 1 3 "x", replace ~role:Muted 1 3 "y"
    ; replace 0 6 "x", replace 1 5 "y"
    ]
    ~f:(fun (a, b) ->
      rejects "abcdef" [ a; style 0 6 Accent; b ];
      rejects "abcdef" [ b; a ]);
  let a = replace 0 3 "abc" and b = replace 3 6 "def" in
  let s = snapshot "abcdef" [ b; style 0 6 Literal; a ] in
  [%test_result: Snapshot.Operation.t list] (Snapshot.operations s)
    ~expect:[ a; style 0 6 Literal; b ]
;;

let%test_unit "operation ordering and explicit style precedence are input-order independent" =
  let input =
    [ style 0 12 Muted; style 2 10 Literal; style 4 6 Accent
    ; style 8 12 Muted; style 8 12 Literal; style 12 14 Literal
    ; style 4 6 Accent; style 8 12 Accent; replace ~role:Muted 4 6 "XY"
    ]
  in
  let expected =
    [ Some Snapshot.Role.Muted; Some Muted; Some Literal; Some Literal
    ; Some Accent; Some Accent; Some Literal; Some Literal
    ; Some Accent; Some Accent; Some Accent; Some Accent
    ; Some Literal; Some Literal; None
    ]
  in
  let reference = snapshot "abcdefghijklmn" input in
  List.iter [ input; List.rev input; List.drop input 3 @ List.take input 3 ] ~f:(fun ops ->
    let s = snapshot "abcdefghijklmn" ops in
    [%test_result: Snapshot.Operation.t list] (Snapshot.operations s)
      ~expect:(Snapshot.operations reference);
    [%test_result: Snapshot.Role.t option list]
      (List.init 15 ~f:(Snapshot.style_at s)) ~expect:expected);
  [%test_result: Snapshot.Role.t option]
    (Snapshot.style_at (snapshot "abcdef" [ style 0 6 Accent; style 2 4 Muted ]) 2)
    ~expect:(Some Muted);
  let s = snapshot "abc" [ replace ~role:Accent 0 1 "x" ] in
  [%test_result: Snapshot.Role.t option] (Snapshot.style_at s 0) ~expect:None
;;

let%test_unit "limits reject atomically and accept exact boundaries, without overflow" =
  let limits : Snapshot.Limits.t =
    { max_source_bytes = 6; max_operations = 3
    ; max_replacement_bytes = 3; max_total_replacement_bytes = 5
    }
  in
  ignore (snapshot ~limits "abcdef"
            [ replace 0 1 "abc"; replace 1 2 "é"; style 0 6 Muted ] : Snapshot.t);
  rejects ~limits "abcdefg" [];
  rejects ~limits "abcdef" (List.init 4 ~f:(fun _ -> style 0 1 Accent));
  rejects ~limits "abcdef" [ replace 0 1 "abcd" ];
  rejects ~limits "abcdef" [ replace 0 1 "abc"; replace 1 2 "abc" ];
  rejects ~limits "abcdef" [ replace 0 1 "éé" ];
  List.iter
    [ { limits with max_source_bytes = -1 }; { limits with max_operations = -1 }
    ; { limits with max_replacement_bytes = -1 }
    ; { limits with max_total_replacement_bytes = -1 }
    ]
    ~f:(fun limits -> rejects ~limits "" []);
  let zero : Snapshot.Limits.t =
    { max_source_bytes = 0; max_operations = 0
    ; max_replacement_bytes = 0; max_total_replacement_bytes = 0
    }
  in
  ignore (snapshot ~limits:zero "" [] : Snapshot.t);
  rejects ~limits:{ zero with max_source_bytes = 1 } "x" [ style 0 1 Accent ];
  let unlimited : Snapshot.Limits.t =
    { max_source_bytes = Int.max_value; max_operations = Int.max_value
    ; max_replacement_bytes = Int.max_value; max_total_replacement_bytes = Int.max_value
    }
  in
  ignore (snapshot ~limits:unlimited "abc" [ replace 0 1 "x"; replace 1 2 "y" ]
          : Snapshot.t);
  (* Budget errors precede malformed data; no UTF-8/index work is needed. *)
  let error = create ~limits:zero "\255" [] |> Result.error |> Option.value_exn in
  [%test_result: string] (Error.to_string_hum error)
    ~expect:"Snapshot.create: source byte limit exceeded"
;;

let%test_unit "default count and replacement-byte caps" =
  let defaults = Snapshot.Limits.default in
  let styles = List.init defaults.max_operations ~f:(fun _ -> style 0 1 Accent) in
  ignore (snapshot "x" styles : Snapshot.t);
  rejects "x" (style 0 1 Accent :: styles);
  ignore (snapshot "x" [ replace 0 1 (String.make defaults.max_replacement_bytes 'x') ]
          : Snapshot.t);
  rejects "x" [ replace 0 1 (String.make (defaults.max_replacement_bytes + 1) 'x') ];
  let replacements = List.init 16 ~f:(fun i ->
    replace i (i + 1) (String.make 4096 'x'))
  in
  ignore (snapshot (String.make 17 'a') replacements : Snapshot.t);
  rejects (String.make 17 'a') (replace 16 17 "x" :: replacements)
;;

let%test_unit "indexed intersections retain long overlaps and exclude touching endpoints" =
  let s = snapshot (String.make 100_000 'x')
      (style 0 100_000 Muted
       :: List.init 4000 ~f:(fun i -> style (i * 25) (i * 25 + 3) Accent))
  in
  [%test_result: Snapshot.Operation.t list]
    (Snapshot.intersecting s ~start:90_001 ~stop:90_027)
    ~expect:[ style 0 100_000 Muted; style 90_000 90_003 Accent; style 90_025 90_028 Accent ];
  [%test_result: Snapshot.Operation.t list]
    (Snapshot.intersecting s ~start:3 ~stop:25)
    ~expect:[ style 0 100_000 Muted ];
  List.iter [ 0, 0; 10, 5; 100_000, 100_100; Int.min_value, 0 ] ~f:(fun (start, stop) ->
    [%test_result: Snapshot.Operation.t list] (Snapshot.intersecting s ~start ~stop) ~expect:[]);
  List.iter [ -1; 0; 1; 3; 4; 25; 90_000; 99_999; 100_000; Int.max_value; Int.min_value ]
    ~f:(fun offset ->
      let lookup = Snapshot.lookup_from s offset in
      List.iter [ offset; offset; 25; 90_001; 90_003; 99_999; 0; -1; 5 ] ~f:(fun at ->
        [%test_result: Snapshot.Role.t option] (lookup at) ~expect:(Snapshot.style_at s at)))
;;

let%test_unit "style sweep and interval index agree with independent brute-force oracles" =
  let random = Random.State.make [| 20261117 |] in
  for _ = 1 to 100 do
    let styles = List.init 80 ~f:(fun _ ->
      let start = Random.State.int random 40 in
      let stop = start + 1 + Random.State.int random (40 - start) in
      let role = List.nth_exn [ Snapshot.Role.Accent; Literal; Muted ]
          (Random.State.int random 3) in
      style start stop role)
    in
    let input = styles @ List.take styles 20 @ [ replace ~role:Muted 0 1 "x" ] in
    let s = snapshot (String.make 40 'x') input in
    for offset = -1 to 40 do
      let expected =
        List.filter_map styles ~f:(function
          | Snapshot.Operation.Style { range; role }
            when range.start <= offset && offset < range.stop ->
            Some (range.stop - range.start, role)
          | _ -> None)
        |> List.min_elt ~compare:[%compare: int * Snapshot.Role.t]
        |> Option.map ~f:snd
      in
      [%test_result: Snapshot.Role.t option] (Snapshot.style_at s offset) ~expect:expected;
      [%test_result: Snapshot.Role.t option] (Snapshot.role_at s offset) ~expect:expected;
      let start = offset and stop = offset + Random.State.int random 8 in
      let expected =
        if start >= stop then [] else
        List.filter (Snapshot.operations s) ~f:(fun operation ->
          let range = Snapshot.Operation.range operation in
          range.start < stop && start < range.stop)
      in
      [%test_result: Snapshot.Operation.t list] (Snapshot.intersecting s ~start ~stop)
        ~expect:expected
    done;
    [%test_result: Snapshot.Operation.t list]
      (Snapshot.operations (snapshot (String.make 40 'x') (List.rev input)))
      ~expect:(Snapshot.operations s)
  done
;;
