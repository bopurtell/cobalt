#!/usr/bin/env bash
# Provision a disposable CI-only switch. Never use the developer's opam root.
set -euo pipefail
cd "$(dirname "$0")/../.."

# Match the supported compiler and package family in docs/source-install.md.
# Repository commits are shared with Silver's pinned release toolchain.
default_revision=e26fd89e85f66b0e908485eab0a545cb9e3d478f
ox_revision=afddc8337950dbc02863fe30ae58735a1cf2719f
compiler=5.2.0minus39
jane=v0.18~preview.130.106+341
dune_version=3.24.2
opam=/usr/bin/opam
export LC_ALL=C.UTF-8

die() {
    echo "toolchain.sh: $*" >&2
    exit 1
}

key() {
    local fingerprint
    fingerprint=$(
        {
            printf '%s\n' "$(uname -s)" "$(uname -m)" "$(id -u):$(id -g)" \
                "$OPAMROOT" "$OPAMSWITCH" "${OPAMJOBS:-2}" "${ImageVersion:-}"
            cat /etc/os-release
            dpkg-query -W -f='${Package}\t${Architecture}\t${Version}\n' | LC_ALL=C sort
            sha256sum cobalt.opam dune-project scripts/ci/toolchain.sh .github/workflows/ci.yml
        } | sha256sum | cut -d ' ' -f1
    )
    printf 'cobalt-native-v1-%s-%s\n' "$(uname -m)" "$fingerprint"
}

host() {
    sudo apt-get update
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        autoconf build-essential bzip2 ca-certificates curl git gzip libgmp-dev libsqlite3-dev \
        ncurses-term opam pkg-config procps python3 ripgrep rsync tmux unzip xz-utils zlib1g-dev
}

require_ci_root() {
    # Refuse any other root, including aliases and symlinks, before removing
    # files left by a partial cache extraction. Never clean ~/.opam.
    [[ $EUID != 0 && -n ${HOME:-} &&
        $OPAMROOT == "$HOME/.cobalt-ci-opam" &&
        $OPAMROOT == "$(realpath -m -- "$OPAMROOT")" &&
        $OPAMSWITCH == 5.2.0+ox ]] ||
        die "expected a non-root user, OPAMROOT=$HOME/.cobalt-ci-opam and OPAMSWITCH=5.2.0+ox"
}

snapshot() {
    local repository=$1 revision=$2 destination=$3
    mkdir -p "$destination"
    curl -fsSL --retry 3 "https://codeload.github.com/$repository/tar.gz/$revision" |
        tar -xz --strip-components=1 -C "$destination"
}

installed_packages() {
    "$opam" list --readonly --switch="$OPAMSWITCH" --installed \
        --columns=name,version --short | awk '{print $1, $2}' | LC_ALL=C sort
}

verify() {
    [[ -f $OPAMROOT/cobalt-ci-key && -f $OPAMROOT/cobalt-ci-packages ]] ||
        die 'toolchain provisioning did not complete'
    [[ $(cat "$OPAMROOT/cobalt-ci-key") == "$(key)" ]] ||
        die 'restored toolchain has a different fingerprint'
    [[ -w $OPAMROOT/$OPAMSWITCH && -z $(find "$OPAMROOT" ! -uid "$EUID" -print -quit) ]] ||
        die 'switch is not writable or opam root contains files owned by another user'
    installed_packages | diff -u "$OPAMROOT/cobalt-ci-packages" -
    if grep -q '^cobalt[[:space:]]' "$OPAMROOT/cobalt-ci-packages"; then
        die 'Cobalt itself must not be installed in the cached switch'
    fi
    local pin
    for pin in "oxcaml-compiler $compiler" "dune $dune_version" "bonsai $jane"; do
        grep -Fxq "$pin" "$OPAMROOT/cobalt-ci-packages" || die "missing pinned package: $pin"
    done
    [[ $("$OPAMROOT/$OPAMSWITCH/bin/ocamlopt" -version) == 5.2.0+ox ]] ||
        die 'incorrect compiler version'
    [[ $("$OPAMROOT/$OPAMSWITCH/bin/dune" --version) == "$dune_version" ]] ||
        die 'incorrect Dune version'
    echo 'Verified CI toolchain.'
}

provision() {
    local expected_key
    expected_key=$(key)
    if [[ -e $OPAMROOT ]]; then
        chmod -R u+rwX "$OPAMROOT"
        rm -rf -- "$OPAMROOT"
    fi
    mkdir -p "$OPAMROOT"
    snapshot ocaml/opam-repository "$default_revision" "$OPAMROOT/snapshots/default"
    snapshot oxcaml/opam-repository "$ox_revision" "$OPAMROOT/snapshots/ox"

    # A disposable hosted runner may restrict unprivileged user namespaces.
    # CI has no shared user state; do not require opam's bubblewrap sandbox.
    "$opam" init --bare --no-setup --no-opamrc --yes --disable-sandboxing \
        default "$OPAMROOT/snapshots/default"
    "$opam" repository add --dont-select --yes ox "$OPAMROOT/snapshots/ox"
    "$opam" switch create --no-switch --yes --jobs="$OPAMJOBS" --repos=ox,default \
        "$OPAMSWITCH" --packages="ocaml-variants.5.2.0+ox,oxcaml-compiler.$compiler"
    # Version pins also constrain the subsequent deps-only solver invocation.
    "$opam" pin add --switch="$OPAMSWITCH" --yes --no-action --kind=version dune "$dune_version"
    "$opam" pin add --switch="$OPAMSWITCH" --yes --no-action --kind=version bonsai "$jane"
    "$opam" install --switch="$OPAMSWITCH" --yes --jobs="$OPAMJOBS" \
        --with-test --deps-only ./cobalt.opam
    "$opam" clean --switch="$OPAMSWITCH" --yes --download-cache --switch-cleanup

    # A host dependency added by opam would invalidate the pre-restore key.
    [[ $(key) == "$expected_key" ]] ||
        die 'host packages changed during provisioning; update the host prerequisites'
    installed_packages > "$OPAMROOT/cobalt-ci-packages"
    printf '%s\n' "$expected_key" > "$OPAMROOT/cobalt-ci-key"
    verify
}

case ${1:-} in
    host) host ;;
    key) key ;;
    provision|verify)
        require_ci_root
        # Use the same system tools as apt provisioned, even if the hosted
        # image exposes other compiler/toolchain versions earlier on PATH.
        export PATH=/usr/bin:/bin
        export OPAMJOBS=${OPAMJOBS:-2}
        "$1"
        ;;
    *) die 'usage: toolchain.sh host|key|provision|verify' ;;
esac
