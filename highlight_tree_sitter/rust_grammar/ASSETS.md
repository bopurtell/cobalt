# Rust grammar assets

Source: [tree-sitter/tree-sitter-rust](https://github.com/tree-sitter/tree-sitter-rust),
tag **`v0.24.0`**, commit **`18b0515fca567f5a10aee9978c6d2640e878671a`**.
[Pinned archive](https://codeload.github.com/tree-sitter/tree-sitter-rust/tar.gz/18b0515fca567f5a10aee9978c6d2640e878671a).

The generated parser (Tree-sitter CLI v0.25.3, language ABI 15), external scanner,
node metadata and C headers are upstream files without local changes. The
parser is stored as a gzip stream (`gzip -n -9 -c src/parser.c`, gzip 1.14).
Normal builds use gzip and the C toolchain, not a Rust compiler, Tree-sitter CLI
or network. `LICENSE` preserves the upstream MIT notice (Maxim Sokolov, 2017);
`LICENSE.tree-sitter` preserves the separate MIT notice for the Tree-sitter headers.

`../rust_queries.ml` uses predicate-free captures against these grammar symbols.
Colors for attributes, macros, lifetimes, declarations, literals and comments
are structural, not semantic. No macro expansion or name resolution is performed.
The configuration is `tree-sitter-rust.18b0515f/cobalt-rust-structural-v1`; bump
the query version when changing capture behavior.

## Checksums (SHA-256)

| Asset | SHA-256 |
| --- | --- |
| Upstream archive | `af3dc21a2985201f764eb94709f09277500fb732f1863f9bdd6371147ca7afe7` |
| Expanded `parser.c` | `a0f424079fd2ba8fe6ae29538e4a773e43c7a1271e6962eb6e8185f67a5c0db9` |
| `parser.c.gz` | `41638b2ec85036678c4cf456239dbafd4e26751c7f26de1e4d7638e175823afa` |
| `scanner.c` | `77faa4943da96dcb17d9c2a735bdbf7702287b52a1d2971117b167e47e318620` |
| `node-types.json` | `7aa048da68d64014402935bec749d57e05b1fd0d7fee1d111edfffc537342e1b` |
| `tree_sitter/parser.h` | `11b654fbba7770b1c710cc14b169be2deb5d89c0f87233d4605037c26c1ff657` |
| `tree_sitter/alloc.h` | `b29c1c9fb7cc82f58c84b376df1297d6e2737a1d655fd356db0859e3c29c2fea` |
| `tree_sitter/array.h` | `5bdf6ed1a78e3409fd443e085ca967a64c188a5d082aaf7f819bccd53a471c94` |
| `LICENSE` | `31d5b6f4243d5c7c6e1c4ebbbb9f6407bd1457a08bcc4f706521710341acba36` |
| `LICENSE.tree-sitter` | `5f9cf9fb6acb1972b35ae29119ce563bb60ec097656bc4b69b9bac2d04c7a147` |
