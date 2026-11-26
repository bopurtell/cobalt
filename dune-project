(lang dune 3.17)

(name cobalt)

(generate_opam_files true)

(license MIT)

(package
 (name cobalt)
 (synopsis "A small modal programmer's editor")
 (description
  "Cobalt is a modal terminal editor with a tile-based workspace, a UI-independent editing core, and a Bonsai_term frontend.")
 (depends
  (ocaml
   (>= 5.2))
  (tree-sitter
   (= 0.1.0))
  core
  core_unix
  async
  yojson
  base64
  bonsai
  bonsai_term
  notty-community
  lsp
  jsonrpc
  ppx_jane
  (bonsai_test :with-test)
  (bonsai_term_test :with-test)
  (expect_test_helpers_core :with-test)
  (expect_test_helpers_async :with-test)))
