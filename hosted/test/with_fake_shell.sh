set -eu

test_exe=$1
root=$(mktemp -d "$PWD/hosted-toggle-XXXXXX")
trap 'rm -f "$root/document.txt" "$root/test-shell" "$root/shells.log"; rmdir "$root"' EXIT
printf 'seed\n' > "$root/document.txt"
: > "$root/shells.log"
cat > "$root/test-shell" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" >> "$HOSTED_TOGGLE_TEST_ROOT/shells.log"
printf 'STARTED_%s\n' "$$"
while IFS= read -r input; do
    printf 'REPLY_%s_%s\n' "$$" "$input"
done
EOF
chmod 700 "$root/test-shell"
SHELL="$root/test-shell" HOSTED_TOGGLE_TEST_ROOT="$root" "$test_exe"
