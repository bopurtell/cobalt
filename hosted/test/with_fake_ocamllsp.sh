set -eu

test_exe=$1
fake_server=$(realpath "$2")
root=$(mktemp -d "$PWD/hosted-lsp-XXXXXX")
trap 'rm -f "$root/first.ml" "$root/dune-project" "$root/ocamllsp" "$root/lsp.log"; rmdir "$root"' EXIT
printf 'let answer = 42\n' > "$root/first.ml"
printf '(lang dune 3.17)\n' > "$root/dune-project"
cat > "$root/ocamllsp" <<'EOF'
#!/bin/sh
exec "$HOSTED_LSP_FAKE_SERVER" -log "$HOSTED_LSP_TEST_ROOT/lsp.log"
EOF
chmod 700 "$root/ocamllsp"
PATH="$root:$PATH" HOSTED_LSP_FAKE_SERVER="$fake_server" HOSTED_LSP_TEST_ROOT="$root" \
    "$test_exe"
