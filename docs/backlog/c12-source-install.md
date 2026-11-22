# C12 — Install Cobalt from a clone

**Status:** Proposed.

## Why

Today a source user can alias `co` to `_build/default/bin/cobalt.exe`, but that
ties daily editing to one checkout and its build directory. Make a fresh clone
installable like Silver: run a script once, then launch the installed editor from
any project. Rerun the same script after updating the clone.

## User-facing contract

With the documented build prerequisites in place:

```sh
git clone https://github.com/bopurtell/cobalt.git
cd cobalt
./install.sh
```

- Build the native Cobalt package and install `cobalt` and `cobalt-open` under
  `~/.local/bin` by default. Install real artifacts, not symlinks or launchers
  into `_build`. No `sudo`. The installed editor can open a file or directory
  outside the clone without an active opam environment.
- Match Silver's `--prefix DIR`, `--switch NAME`, `--jobs N`, and `--help`.
  Prefer `--prefix`, then `COBALT_PREFIX`, then `PREFIX`, then `$HOME/.local`;
  prefer `--switch`, then `OPAM_SWITCH`, then opam's selected switch. Use
  `COBALT_BUILD_JOBS` or a conservative default when `--jobs` is omitted.
  Resolve relative paths from the caller even when the script is invoked
  from outside the checkout.
- On success, print the exact installed path and show how to put its `bin/`
  directory first on `PATH` if needed. Do not edit shell startup files.
  Document how to replace the old alias with `alias co=cobalt` if desired;
  do not install a generic `co` command by default.
- Rerunning with the same prefix updates the installed package. Build before
  installing so a failed build leaves the last successful install alone.
  Document how to remove the installed package without removing editor config
  or unrelated files in a shared prefix.

## Build and dependency policy

[Silver's installer](https://github.com/bopurtell/silver/blob/HEAD/install.sh)
uses an existing opam switch via `opam exec`, builds `@install`, then runs
`dune install --prefix`. It reports missing prerequisites and prints PATH
guidance. Follow that flow, not Silver's ASIC provider checks. Basic Cobalt
installation does not require Silver, an ASIC provider, ripgrep, or language
servers.

Reuse Cobalt's existing Dune `cobalt` package rather than writing a second
artifact list. Its public executables and libraries (including `cobalt.hosted`
and `cobalt.terminal`) should remain installable together. Use a standard or
relative Dune build directory; the [installed consumer example](../../examples/hosted_consumer/README.md#absolute-build-directory-caveat)
documents a Dune 3.24.2 failure with absolute build directories.

Like Silver, v1 expects a compatible existing switch and build dependencies;
it does not create or mutate a switch, add package repositories, or install
system packages. Document and verify the initial setup for the supported
OxCaml/Jane Street toolchain, including the C compiler and `gzip`. Missing
opam, switch, tools, or dependencies should fail nonzero with actionable
guidance (for example, the `opam install --switch=… --deps-only .` command
from the checkout), not leave users guessing at a compiler error.

## Acceptance

- On a clean checkout with no prebuilt binaries, install with an isolated
  `HOME` and verify the default location. Also test a custom prefix containing
  spaces, invoked from outside the checkout with an explicit switch.
- Outside the checkout, with no `_build` access and the switch not on `PATH`,
  run the installed `cobalt --list-themes` and `cobalt-open --help`. In a PTY,
  open an unrelated directory and edit, save, and quit a file from it.
- Verify the installed public libraries still resolve in an independent
  consumer using the documented prefix setup. Rerun the installer and verify
  both commands still work. A failing build must not replace the previous
  install.
- Exercise help, invalid jobs, missing prerequisites, and unwritable prefix.
  Check that PATH guidance identifies the installed command without modifying
  shell files or the opam switch.
- Update the top-level README with clone → install → launch, prerequisites,
  and upgrade/removal instructions. Keep the existing
  [extract-and-run tarball](../releases.md) as the separate no-build option.

**Out of scope:** Bootstrapping opam or OxCaml from scratch, downloading
prebuilt releases from the installer, distro packages, and publishing release
artifacts.
