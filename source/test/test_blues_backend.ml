open! Core
open Cobalt_source

let%expect_test "Blues requires a real project marker and never selects Classic or Verilog" =
  let root = Filename_unix.realpath (Filename_unix.temp_dir "cobalt-blues" "") in
  let lib = Filename.concat root "lib" in
  let database = Filename.concat root "blues_compdb.json" in
  let config = Filename.concat lib "blues.toml" in
  Core_unix.mkdir lib;
  Exn.protect
    ~finally:(fun () ->
      List.iter [ config; database ] ~f:(fun path ->
        if Sys_unix.file_exists_exn path then Core_unix.unlink path);
      Core_unix.rmdir lib;
      Core_unix.rmdir root)
    ~f:(fun () ->
      let path = Filename.concat lib "Package.bsv" in
      let applies file = Blues_backend.applies_to (Filename.concat lib file) in
      assert (not (applies "Package.bsv"));
      assert (Option.is_none (Lsp_client.Config.for_path path));
      Out_channel.write_all database ~data:"[]";
      assert (applies "Package.bsv");
      assert (not (applies "Package.bs"));
      assert (not (applies "Package.sv"));
      assert (not (applies "Package.bsv.bak"));
      assert (Option.is_none (Lsp_client.Config.for_path (Filename.concat lib "Package.bs")));
      let select path = Option.value_exn (Lsp_client.Config.for_path path) in
      let selected = select path in
      assert (String.equal selected.source Blues_backend.source);
      assert (List.equal String.equal selected.args Blues_backend.args);
      assert (String.equal selected.prog (Option.value (Sys.getenv "BLUES_LSP") ~default:"blues"));
      assert (String.equal (selected.language_id path) "bsv");
      assert (String.equal (select (Filename.concat lib "Package.sv")).source "slang-server");
      let project_root () = Lsp_client.Config.root selected path in
      assert (String.equal (project_root ()) root);
      Out_channel.write_all config ~data:{|compdb_path = "../blues_compdb.json"|};
      assert (String.equal (project_root ()) lib);
      printf "%s %s (%s)\n" Blues_backend.prog (String.concat ~sep:" " Blues_backend.args)
        (Blues_backend.language_id path));
  [%expect {| blues lsp (bsv) |}]
;;
