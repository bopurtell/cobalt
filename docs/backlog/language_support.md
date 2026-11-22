# Tickets: Rust, Haskell, and Bluespec support

**Status:** LANG-01 (Rust), LANG-03 (BSV highlighting), and LANG-04 (compiler
feedback) implemented and verified. See [running a project check or build](../editor_reference.md#run-a-bluespec-compiler-check-or-build).
LANG-05 selected Blues for opt-in BSV completion and definition
jumps; see the [real-project evaluation](bsv_language_server_evaluation.md).
LANG-02 (Haskell) and LANG-06 (Bluespec Classic highlighting) remain proposed.
**Requested:** 2026-11-22.

## Goal

Open a source file and get useful highlighting without setup. With the right
toolchain installed, use Cobalt's normal commands to see what's wrong, complete
a name, or jump to its definition wherever those features are supported. For
Bluespec, clickable compiler errors are more valuable than IDE features that
only work on toy examples.

Bluespec SystemVerilog (`.bsv`) and Bluespec Haskell/Classic (`.bs`) are two
syntaxes for the same language, compiled by BSC. They are distinct from standard
Verilog/SystemVerilog and GHC Haskell, respectively.

## Ticket index

| Ticket | Priority | User-visible result |
| --- | --- | --- |
| [LANG-01](#lang-01--rust-editing) | First | Rust highlighting and language intelligence in Cargo projects |
| [LANG-02](#lang-02--haskell-editing) | Independent | Haskell highlighting and language intelligence in a GHC project |
| [LANG-03](#lang-03--bluespec-systemverilog-highlighting) | First for Bluespec | Useful `.bsv` highlighting without any external tool |
| [LANG-04](#lang-04--bluespec-compiler-feedback) | Next for Bluespec | Build/check errors that jump to `.bsv` or `.bs` source |
| [LANG-05](#lang-05--evaluate-bluespec-systemverilog-language-intelligence) | Follow-up | Validate which `.bsv` IDE features are worth shipping |
| [LANG-06](#lang-06--bluespec-classic-highlighting) | Independent | Useful `.bs` highlighting without treating it as `.hs` |

## Shared acceptance

- [ ] Highlighting works on first open without a server or compiler installed,
      stays useful while the file is incomplete, and updates after edits and
      undo. Existing file types keep their current behavior.
- [ ] When a required tool is absent, incompatible, or misconfigured, editing
      and highlighting still work. The relevant status or command reports what
      is unavailable and points to a fix. Keep existing language-server opt-out
      and restart behavior for server-backed features.
- [ ] Use the existing completion, hover, navigation, and findings interactions
      where applicable. Opening a diagnostic or definition in another file
      respects unsaved buffers. No language feature blocks typing.
- [ ] Document the supported file types, setup, and known limits. Cover editor
      behavior with repeatable tests and exercise the claimed tool-backed
      workflows on a real toolchain and representative project before closing.

The implementation is open. Formatting, rename, semantic coloring, and new
keybindings are not required for these tickets.

## LANG-01 — Rust editing

**Goal:** Open `.rs` files in a Cargo project and use normal Cobalt editing
commands without configuring each file or workspace member by hand.

### Acceptance criteria

- [ ] Highlight representative Rust code, including attributes, macros,
      lifetimes, comments, and raw strings.
- [ ] With `rust-analyzer` available, see a diagnostic for a deliberate error and
      see it clear after the fix. Verify hover, completion, and a definition jump
      across source files.
- [ ] Verify the workflow in a standalone crate and in a multi-crate Cargo
      workspace opened from a member file. A jump to a sibling crate works and
      the active root is visible in the Language servers report.
- [ ] Opening a loose `.rs` file still gives a usable editing experience even
      when no Cargo project can be loaded.

## LANG-02 — Haskell editing

**Goal:** Open ordinary `.hs` files and use Haskell language intelligence with
a project-compatible GHC and Haskell Language Server (HLS).

### Acceptance criteria

- [ ] Highlight representative `.hs` source, including layout-sensitive `do`
      and `let` blocks, pragmas, comments, and type signatures.
- [ ] In a Cabal project with a compatible toolchain, see a type error and see
      it clear after the fix. Verify hover, completion, and a jump to a
      definition in another module.
- [ ] Open a module directly from a nested source directory and verify that
      HLS loads the intended project. Document the supported setup, how to
      diagnose a GHC/HLS mismatch, and any untested project layouts.
- [ ] Literate Haskell (`.lhs`) and Bluespec Classic are out of scope.

## LANG-03 — Bluespec SystemVerilog highlighting

**Goal:** Read and edit `.bsv` source even without a Bluespec toolchain.

### Acceptance criteria

- [ ] Highlight representative packages, imports, interfaces, modules, rules,
      methods, and common literal/comment forms in a real BSV file.
- [ ] A half-written rule or method does not strip highlighting from unrelated
      code. `.bsv` files are not sent to Slang; generated `.v` files still get
      regular Verilog support.
- [ ] This ticket can close without a Bluespec compiler or language server.

## LANG-04 — Bluespec compiler feedback

**Goal:** From Cobalt, explicitly run a project's normal BSC check/build and
jump from a compiler finding to the offending source.

### Acceptance criteria

- [ ] Document how to select the project command and run it, including the
      project's own package paths and flags. Opening a file does not run it.
- [ ] A compile error in the current file and one in an imported package show
      up in the existing findings workflow; selecting either opens the right
      source file at the reported location. Cover `.bsv` and `.bs` with real BSC.
- [ ] Results say which run they belong to. Starting another run or editing
      after a run does not present old locations as current. A successful rerun
      clears old compiler findings without clearing unrelated sources.
- [ ] Make it clear whether the command checks saved files. Never save dirty
      buffers implicitly, and distinguish a missing tool or failed launch from
      a successful run with no findings.

## LANG-05 — Evaluate Bluespec SystemVerilog language intelligence

**Goal:** Decide whether an available BSV server adds enough value beyond
highlighting and compiler feedback to ship.

### Acceptance criteria

- [ ] Try the [candidate BSV language server](https://github.com/open-rdma/bluespec-lsp)
      or a better available alternative on a representative multi-package BSC
      project. Exercise hover, completion, cross-package definition jumps, and
      behavior while editing incomplete code.
- [ ] Record what actually works, including how diagnostics differ from BSC
      findings. A server starting or passing a demo fixture is not enough.
- [ ] Record a ship/defer decision. If useful, scope a follow-up for verified
      features and document its limits. If not, keep the highlighting and
      compiler workflows independent of the server.

## LANG-06 — Bluespec Classic highlighting

**Goal:** Make `.bs` files readable without routing them through GHC/HLS or
waiting on a Classic language server.

### Acceptance criteria

- [ ] Highlight representative Classic source, including package/module
      structure, rules, methods, types, comments, and literals. Check against
      real `.bs` files, not just equivalent Haskell examples.
- [ ] Opening `.bs` never starts HLS. In a project with both `.bs` and `.bsv`,
      each file retains highlighting for its own syntax.
- [ ] Compiler feedback is tracked in LANG-04; semantic navigation and
      completion are not required for this ticket.

## References

- Cobalt's current [syntax highlighting](../editor_reference.md#syntax-highlighting),
  [language servers](../editor_reference.md#language-servers-ocamllsp-and-slang-server),
  and [navigation](../editor_reference.md#hover-and-symbol-navigation).
- [BSC](https://github.com/B-Lang-org/bsc) and the
  [B-Lang Classic syntax grammar](https://github.com/B-Lang-org/language-bh).
- [Rust Tree-sitter grammar](https://github.com/tree-sitter/tree-sitter-rust)
  and [HLS/GHC compatibility](https://haskell-language-server.readthedocs.io/en/latest/support/ghc-version-support.html).
