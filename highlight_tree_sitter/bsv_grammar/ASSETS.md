# Bluespec SystemVerilog grammar assets

Source: [6eanut/tree-sitter-bsv](https://github.com/6eanut/tree-sitter-bsv),
commit **`ed1a91ebec670b1040695a3a57b8c66ad5baf5c5`**.
[Pinned archive](https://codeload.github.com/6eanut/tree-sitter-bsv/tar.gz/ed1a91ebec670b1040695a3a57b8c66ad5baf5c5).
This is a BSV-specific grammar, not Verilog, Bluespec Classic or a server grammar
loaded at runtime.

The pinned [grammar source](https://github.com/6eanut/tree-sitter-bsv/blob/ed1a91ebec670b1040695a3a57b8c66ad5baf5c5/grammar.js)
names Jiakai Xu and declares MIT, matching the license declarations in
`tree-sitter.json`, `package.json` and `Cargo.toml`. That commit lacks a standalone
license file; the bundled `LICENSE` records the attribution and standard MIT text,
not an upstream file or an inferred copyright year. `LICENSE.tree-sitter` is the
separate, verbatim MIT notice for the generated parser header.

`grammar.js` is retained with one local grammar change (`cobalt-bsv-grammar-v1`):
the all-zero literal is `'0`, not `'0'`, as verified with BSC 2026.07.1.
The regenerated parser uses language ABI 14 and no external scanner. Normal builds
expand the parser with gzip; no generator, compiler for BSV, network, language
server or separate query file is needed at runtime.

`../bsv_queries.ml` is Cobalt-authored and predicate-free. The configuration is
`tree-sitter-bsv.ed1a91eb/cobalt-bsv-grammar-v1/cobalt-bsv-structural-v1`.
Bump the relevant version when changing grammar or query behavior. Captures
are structural, not semantic. On error trees, the provider recolors block
boundary keywords that the grammar recovered as identifiers. The upstream
grammar does not preprocess or expand backtick macros; unsupported or incomplete
syntax can reduce the precision of nearby captures. The representative
`DemoCounter` test fixture also compiles with BSC 2026.07.1; no claim is made that
Tree-sitter accepts every valid BSV program.

## Checksums (SHA-256)

| Asset | SHA-256 |
| --- | --- |
| Upstream archive | `baf4888d0a84f7ba6110fa19d37f20a725cd9bee69aac19d1117c81f8f189c96` |
| Original `grammar.js` | `45b44a03851c2e44bc1be2d3141d1b566bcdf6b0da0d8b28c91e0e9e0313fcf3` |
| Patched `grammar.js` | `4506ad4f7d21ee2953342eb9bf94fb5ad0a6c80954a834d4b1dc2287b6ed7ff0` |
| Expanded `parser.c` | `867dc709f99b6a512f648898ecf79d182976781167d3462fad22d311598e621c` |
| `parser.c.gz` | `9b67ef3ee6e4750ecab0a2778eda1776f4d500411ed1629975649bf600ec3e05` |
| `node-types.json` | `23220b0fdf351aa8fcdc5ca2dd3777d42546b08d72042edaf3177c02a0abfd1e` |
| `tree_sitter/parser.h` | `a1f6ef161fbaf48a0e10fca90ef5290a062462b307b3898aa562993853b9f80a` |
| `LICENSE.tree-sitter` | `5f9cf9fb6acb1972b35ae29119ce563bb60ec097656bc4b69b9bac2d04c7a147` |

## Reproduction

From the repository root, with tree-sitter CLI 0.24.7 (`5e8760bf462c`), Node and gzip:

```sh
dst="$PWD/highlight_tree_sitter/bsv_grammar"
work="$(mktemp -d)"
cp "$dst/grammar.js" "$work/"
(cd "$work" && tree-sitter generate --abi 14)
gzip -n -9 -c "$work/src/parser.c" > "$dst/parser.c.gz"
cp "$work/src/node-types.json" "$dst/"
cp "$work/src/tree_sitter/parser.h" "$dst/tree_sitter/"
```

Compression used gzip 1.14; use the expanded parser hash if the gzip version
differs. The upstream grammar record and development CLI are not build inputs.
