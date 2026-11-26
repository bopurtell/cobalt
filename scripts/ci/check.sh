#!/usr/bin/env bash
# Run inside the development switch, from the checkout (never an installed editor).
set -euo pipefail
cd "$(dirname "$0")/../.."
jobs=${COBALT_BUILD_JOBS:-2}
export LC_ALL=C.UTF-8 DUNE_CACHE=disabled
TIMEFORMAT='Elapsed: %3R seconds'

echo "=== Build Cobalt $(git rev-parse HEAD) ==="
time dune build --root . -j "$jobs"
echo '=== Headless, CLI and simulated Silver peer tests ==='
time dune runtest --root . -j 1 --force
echo '=== Terminal and Markdown smoke tests ==='
# Several tmux/PTY fixtures inherit the launching user's Cobalt preferences.
# Use the same default editor layout locally as on the fresh runner.
smoke_config=$(mktemp -d)
trap 'rm -rf -- "$smoke_config"' EXIT
time XDG_CONFIG_HOME="$smoke_config" dune build --root . -j 1 @smoke @scripts/smoke-markdown
echo '=== Packaging unit tests ==='
time python3 -B -m unittest discover -s packaging/tests -p test_package_release.py
