open! Core
open Cobalt_core

let entries =
  [ { Directory_identity.Entry.id = 1; name = "a"; kind = File }
  ; { Directory_identity.Entry.id = 2; name = "b"; kind = Directory }
  ; { Directory_identity.Entry.id = 3; name = "link"; kind = Symlink }
  ]
let text s = Text_buffer.of_string s |> Result.map_error ~f:Text_buffer.Invalid_text.to_string_hum |> Result.ok_or_failwith
let plan s = Directory_plan.plan entries (text s)

let%test_unit "pure planner creates, renames symlinks, reorders, and accepts rename dependencies" =
  let operations = plan "@cobalt[2]\tb/\nnew\nfolder/\n@cobalt[1]\tc\n@cobalt[3]\talias" |> Or_error.ok_exn in
  assert (List.equal Directory_plan.equal_operation operations
    [ Create_file "new"; Create_directory "folder"
    ; Rename { id = 1; source = "a"; destination = "c" }
    ; Rename { id = 3; source = "link"; destination = "alias" } ]);
  assert (String.is_substring (Directory_plan.summary operations) ~substring:"Rename link -> alias");
  assert (List.is_empty (plan "@cobalt[3]\tlink\n\n@cobalt[2]\tb/\n@cobalt[1]\ta\n" |> Or_error.ok_exn));
  assert (List.length (plan "@cobalt[1]\tb\n@cobalt[2]\ta/\n@cobalt[3]\tlink" |> Or_error.ok_exn) = 2)
;;

let%test_unit "unsupported or ambiguous snapshots reject the entire proposal" =
  List.iter
    [ "@cobalt[1]\ta\n@cobalt[2]\tb/\n@cobalt[3]\tlink\n@cobalt[1]\tcopy"
    ; "@cobalt[1]\tb\n@cobalt[2]\tb/\n@cobalt[3]\tlink" (* occupied destination *)
    ; "@cobalt[1]\ta\n@cobalt[2]\tb/\n@cobalt[3]\tlink\na" (* create collision *)
    ; "@cobalt[1]\ta/\n@cobalt[2]\tb/\n@cobalt[3]\tlink" (* type change *)
    ; "@cobalt[99]\ta\n@cobalt[2]\tb/\n@cobalt[3]\tlink"
    ; "@cobalt[1]\ta\n@cobalt[2]\tb/\n@cobalt[3]\tlink\n../escape"
    ; "@cobalt[1]\ta\n@cobalt[2]\tb/\n@cobalt[3]\tlink\n\\x00"
    ; "@cobalt[1]\ta\n@cobalt[2]\tb/\n@cobalt[3]\tlink\nnew\nnew/"
    ] ~f:(fun snapshot -> assert (Result.is_error (plan snapshot)))
;;

let%test_unit "explicit copied rows have source identity independent of deletion and moves" =
  let operations = plan "@cobalt[2]\tb/\n@cobalt[3]\t../other/link\n@copy[1]\tcopy\n@copy[1]\t../other/copy" |> Or_error.ok_exn in
  assert (List.equal Directory_plan.equal_operation operations
    [ Delete { id = 1; source = "a"; kind = File }
    ; Rename { id = 3; source = "link"; destination = "../other/link" }
    ; Copy { id = 1; source = "a"; destination = "copy"; kind = File }
    ; Copy { id = 1; source = "a"; destination = "../other/copy"; kind = File } ]);
  assert (String.is_substring (Directory_plan.summary operations) ~substring:"Permanently delete");
  assert (Result.is_error (plan "@copy[99]\tcopy"));
  assert (Result.is_error (plan "@cobalt[1]\ta\n@cobalt[2]\tb/\n@cobalt[3]\tlink\n@copy[2]\tcopy"));
  assert (Result.is_error (plan "@cobalt[1]\ta\n@cobalt[2]\tb/\n@cobalt[3]\tlink\n@copy[1]\tcopy\n@copy[1]\tcopy"))
;;
