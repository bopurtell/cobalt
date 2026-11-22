# Install Cobalt from source

For a no-build alternative, see the [extract-and-run Linux archive](releases.md).
For contributing without installing, see [Development](development.md#build-and-run).

## Prerequisites

- Git to fetch the source, a POSIX shell, and [opam](https://opam.ocaml.org/).
- An existing [OxCaml](https://oxcaml.org/) opam switch with the Jane Street
  preview package family. The tested combination is a switch named `5.2.0+ox`
  with `oxcaml-compiler.5.2.0minus39` (`ocamlopt -version` reports
  `5.2.0+ox`), Jane Street packages `v0.18~preview.130.106+341`, and
  Dune 3.24.2. A stock OCaml 5.2 switch is not an equivalent toolchain.
  Dune's project language is 3.17.
- The switch's configured C compiler (GCC on the tested Linux switch) and
  `gzip` for the bundled native parsers. Install system dependencies for your
  chosen opam packages as reported by opam; no system libvterm is needed.

Check the existing switch and its repositories:

```sh
opam switch list
opam exec --switch=5.2.0+ox -- ocamlopt -version
opam repository list --switch=5.2.0+ox
```

Replace `5.2.0+ox` if your compatible switch has a different name. The tested
switch uses [the OxCaml opam repository](https://github.com/oxcaml/opam-repository)
ahead of the standard opam repository; it supplies the Jane Street preview
packages and OxCaml variants of packages such as `lsp`, `jsonrpc`, and
`notty-community`. If your existing OxCaml switch does not yet have this
repository configured, add it to that switch separately before installing the
dependencies:

```sh
opam repository add --switch=5.2.0+ox --rank=1 ox \
git+https://github.com/oxcaml/opam-repository.git
```

Then prepare Cobalt's build dependencies from the root of the clone:

```sh
opam install --switch=5.2.0+ox --deps-only .
```

If opam cannot find a compatible solution, check that your switch's compiler
and repository snapshot offer the package family above. Cobalt requires
`tree-sitter` 0.1.0; the full dependency list is in [`cobalt.opam`](../cobalt.opam).

The explicit `opam install --deps-only` command above is a setup step you run
if needed. `install.sh` itself does not create or change switches, add opam
repositories, or install opam/system dependencies. Neither Silver nor an ASIC
provider, ripgrep, or language servers are prerequisites for basic editing.
An OCaml compiler on your runtime `PATH` is optional unless you use executable
[`config.ml`](configuration.md).

## Install and launch

```sh
./install.sh
export PATH="$HOME/.local/bin:$PATH"
cd /path/to/your/project
cobalt .
```

`install.sh` builds the Dune `cobalt` package and installs its executables and
public libraries. The installed commands are real native binaries, not links or
wrappers pointing back to the clone. You don't need `opam exec` or the build
directory to launch them.

| Setting | Precedence |
| --- | --- |
| Prefix | `--prefix DIR`, `COBALT_PREFIX`, `PREFIX`, then `$HOME/.local` |
| Switch | `--switch NAME`, `OPAM_SWITCH`, then opam's selected switch |
| Jobs | `--jobs N`, `COBALT_BUILD_JOBS`, then `4` |

Run `./install.sh --help` for usage. You can invoke the script by path from
another directory. Choose a writable prefix outside the opam switch. Relative
prefix paths (and explicit local switch paths such as `./`) are resolved from
your working directory, not the checkout:

```sh
/path/to/cobalt/install.sh --switch 5.2.0+ox --prefix './my tools' --jobs 4
```

The installer prints the exact binaries and a shell command putting their
directory first on `PATH`. It never edits shell startup files. If you already
have a `co` alias pointing to `_build`, replace it in your shell config with
`alias co=cobalt` (or remove it). No `co` executable is installed.

For embedding, see the [external hosted consumer](../examples/hosted_consumer/README.md#isolated-build-and-run)
for the compatible switch and `OCAMLPATH` setup.

## Upgrade

Update your clone and rerun the installer with the same prefix and switch.
Building finishes before copying any installed files, so a failed build leaves
the previous installation intact. If copying fails (for example, the disk fills
up), correct the problem and rerun the installer.

## Uninstall

From the checkout used to install (ideally the same revision and optional
modules), run the Dune package-specific uninstall with the same prefix and
switch. Keep the generated `_build` manifest, or rebuild it first:

```sh
switch=5.2.0+ox
prefix="$HOME/.local"  # use your actual absolute install prefix
unset DUNE_WORKSPACE DESTDIR
opam exec --readonly --switch="$switch" -- dune build --root . --build-dir _build \
  --profile release --pkg=disabled --only-packages cobalt --promote-install-files=false -j 4 @install
opam exec --readonly --switch="$switch" -- dune uninstall --root . --build-dir _build \
  --profile release --pkg=disabled --prefix "$prefix" -j 4 cobalt
```

Add `--dry-run` to the uninstall invocation to preview the files it will remove.
This removes only the paths in the Cobalt package manifest. It does not remove
your editor configuration or unrelated files in a shared prefix. Do not delete
the whole prefix to uninstall Cobalt.
