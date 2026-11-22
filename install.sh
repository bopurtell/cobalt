#!/bin/sh
# Build from this checkout, then install into a user-managed prefix.
set -eu

usage() {
    cat <<'EOF'
Usage: ./install.sh [--prefix DIR] [--switch NAME] [--jobs N]

Build and install Cobalt from this checkout using an existing opam switch.
  --prefix DIR   Install prefix (COBALT_PREFIX, PREFIX, then $HOME/.local).
  --switch NAME  Opam switch (OPAM_SWITCH, then opam's selected switch).
  --jobs N       Positive build job count (COBALT_BUILD_JOBS, then 4).
  -h, --help     Show this help and exit.

Relative paths are resolved from the directory where you run the script.
See docs/source-install.md for prerequisites, updates and removal.
EOF
}

die() {
    printf 'install.sh: %s\n' "$*" >&2
    exit 1
}

# Print a single POSIX-shell word, including when the value contains quotes.
quote() {
    printf "'"
    word=$1
    while [ "${word#*\'}" != "$word" ]; do
        printf "%s'\\\\''" "${word%%\'*}"
        word=${word#*\'}
    done
    printf "%s'" "$word"
}

prefix=${COBALT_PREFIX:-${PREFIX:-}}
switch=${OPAM_SWITCH:-}
jobs=${COBALT_BUILD_JOBS:-4}

while [ "$#" -gt 0 ]; do
    case $1 in
        -h|--help) usage; exit 0 ;;
        --prefix|--switch|--jobs)
            case ${2:-} in
                ''|--*) die "$1 requires a value (see --help)." ;;
            esac
            case $1 in
                --prefix) prefix=$2 ;;
                --switch) switch=$2 ;;
                --jobs) jobs=$2 ;;
            esac
            shift 2 ;;
        *) die "Unknown argument: $1 (see --help)." ;;
    esac
done

case $jobs in
    ''|*[!0-9]*) die "--jobs / COBALT_BUILD_JOBS must be a positive integer." ;;
esac
case $jobs in
    *[1-9]*) ;;
    *) die "--jobs / COBALT_BUILD_JOBS must be a positive integer." ;;
esac

if [ -z "$prefix" ]; then
    [ -n "${HOME:-}" ] || die 'Set HOME, COBALT_PREFIX, or pass --prefix DIR.'
    prefix=$HOME/.local
fi
case $prefix in
    /*) ;;
    *) prefix=$PWD/$prefix ;;
esac
case $switch in
    /*) ;;
    .|..|*/*) switch=$PWD/$switch ;;
esac

command -v opam >/dev/null 2>&1 ||
    die 'opam is required; install opam and prepare an OxCaml switch (docs/source-install.md).'
if [ -z "$switch" ]; then
    switch=$(opam switch show --readonly) ||
        die 'No usable opam switch selected; prepare a switch and pass --switch NAME (docs/source-install.md).'
fi
[ -n "$switch" ] || die 'No opam switch selected; pass --switch NAME (docs/source-install.md).'

repo=$(CDPATH= cd -P -- "$(dirname -- "$0")" && pwd -P)

in_switch() {
    opam exec --readonly --switch="$switch" -- "$@"
}

in_switch true ||
    die "Cannot use opam switch '$switch'; check 'opam switch list' or pass --switch NAME."

dependency_help() {
    printf 'From the checkout, install any missing build dependencies in the compatible switch:\n  cd ' >&2
    quote "$repo" >&2
    printf '\n  opam install --switch=' >&2
    quote "$switch" >&2
    printf ' --deps-only .\nSee docs/source-install.md for the supported toolchain.\n' >&2
}

if ! in_switch sh -c '
    for tool in dune ocamlopt gzip; do
        command -v "$tool" >/dev/null 2>&1 || {
            printf "Required build tool not found: %s\n" "$tool" >&2
            exit 1
        }
    done
    compiler=$(ocamlopt -config-var c_compiler) || exit 1
    command -v "${compiler%% *}" >/dev/null 2>&1 || {
        printf "Install the C compiler configured in the switch: %s\n" "$compiler" >&2
        exit 1
    }
'; then
    dependency_help
    die 'Missing build prerequisites; install the tools above and retry.'
fi

# Catch common prefix errors without creating directories or overwriting a
# previous installation. Dune still reports any errors during the actual copy.
check_destination() {
    destination=$1
    while [ ! -e "$destination" ] && [ ! -L "$destination" ]; do
        destination=$(dirname -- "$destination")
    done
    [ -d "$destination" ] && [ -w "$destination" ] && [ -x "$destination" ] ||
        die "Install destination is not writable: $destination. Choose a writable --prefix."
}
check_destination "$prefix"
check_destination "$prefix/bin"
check_destination "$prefix/lib"

cd -- "$repo"
# Keep the build local: Dune 3.24.2 cannot install some private interfaces
# from an absolute build directory. Do not let packaging redirection change
# the destination reported to the user.
unset DUNE_WORKSPACE DESTDIR
printf 'Building Cobalt with opam switch %s (%s jobs)…\n' "$switch" "$jobs"
if ! in_switch dune build --root . --build-dir _build --profile release --pkg=disabled \
    --only-packages cobalt --promote-install-files=false -j "$jobs" @install; then
    dependency_help
    die 'Build failed; the previous installation has not been changed.'
fi
if ! in_switch dune install --root . --build-dir _build --profile release --pkg=disabled \
    -j "$jobs" --prefix "$prefix" cobalt; then
    die "Dune could not install into '$prefix'; check destination permissions and disk space, then retry."
fi

printf '\nInstalled:\n  %s/bin/cobalt\n  %s/bin/cobalt-open\n\n' "$prefix" "$prefix"
printf 'Put this directory first on PATH if needed:\n  export PATH='
quote "$prefix/bin"
printf ':"$PATH"\n'
