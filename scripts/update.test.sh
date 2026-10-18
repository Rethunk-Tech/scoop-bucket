#!/usr/bin/env bash
# Throwaway-keyring cases for scripts/update.sh: a failed or unsigned SHA256SUMS must not rewrite the manifest.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
fail=0

assert() {
  local name=$1
  shift
  if "$@"; then
    echo "ok $name"
  else
    echo "not ok $name" >&2
    fail=1
  fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

install -d "$work/bin" "$work/keys" "$work/sums"
PATH="$work/bin:$PATH"
export PATH

cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "v9.9.9"
EOF
chmod +x "$work/bin/gh"

cat >"$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""
prev=""
url=""
for a in "$@"; do
  case $prev in
    -o | -*o) out=$a ;;
  esac
  prev=$a
  url=$a
done
file=${url##*/}
src="${FIXTURE_DIR}/${file}"
if [ "${CURL_FAIL-}" = "$file" ]; then
  exit 22
fi
if [ ! -f "$src" ]; then
  exit 22
fi
if [ -n "$out" ]; then
  cp "$src" "$out"
else
  cat "$src"
fi
EOF
chmod +x "$work/bin/curl"

export GNUPGHOME="$work/keys"
install -d -m 700 "$GNUPGHOME"
gpg --batch --passphrase '' --quick-generate-key "scoop-bucket-test@example.com" default default never
fpr=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" {print $10; exit}')
gpg --batch --export --armor >"$work/throwaway.asc"
amd=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
arm=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
printf '%s  mortar-windows-amd64.exe\n%s  mortar-windows-arm64.exe\n' "$amd" "$arm" >"$work/sums/SHA256SUMS"
gpg --batch --yes --local-user "$fpr" --detach-sign --armor -o "$work/sums/SHA256SUMS.asc" "$work/sums/SHA256SUMS"

setup_tree() {
  local dest=$1
  rm -rf "$dest"
  install -d "$dest/scripts" "$dest/bucket"
  cp "$repo/bucket/mortar.json" "$dest/bucket/mortar.json"
  sed "s/D8B1C4C205C5FB3633CB8B9900B75959B637DCB5/$fpr/" "$repo/scripts/update.sh" >"$dest/scripts/update.sh"
  chmod +x "$dest/scripts/update.sh"
  cp "$work/throwaway.asc" "$dest/scripts/mortar-archive-keyring.asc"
}

run_update() {
  local dest=$1
  env -u GNUPGHOME PATH="$PATH" FIXTURE_DIR="$FIXTURE_DIR" CURL_FAIL="${CURL_FAIL:-}" "$dest/scripts/update.sh"
}

before=$(jq -c '{version, architecture}' "$repo/bucket/mortar.json")

# A transport failure (not a verified 404) must not hash binaries unsigned.
case1=$work/case-curl-fail
setup_tree "$case1"
export FIXTURE_DIR="$work/sums" CURL_FAIL=SHA256SUMS
if run_update "$case1" >/dev/null 2>"$work/case1.err"; then
  assert "curl-fail-exits" false
else
  assert "curl-fail-exits" true
fi
assert "curl-fail-names-sums" grep -q SHA256SUMS "$work/case1.err"
after=$(jq -c '{version, architecture}' "$case1/bucket/mortar.json")
assert "curl-fail-leaves-manifest" [ "$after" = "$before" ]
unset CURL_FAIL

# Missing signature file is fatal.
case2=$work/case-no-asc
setup_tree "$case2"
export FIXTURE_DIR="$work/sums-no-asc"
install -d "$FIXTURE_DIR"
cp "$work/sums/SHA256SUMS" "$FIXTURE_DIR/SHA256SUMS"
if run_update "$case2" >/dev/null 2>"$work/case2.err"; then
  assert "missing-asc-exits" false
else
  assert "missing-asc-exits" true
fi
assert "missing-asc-names-asc" grep -q SHA256SUMS.asc "$work/case2.err"
after=$(jq -c '{version, architecture}' "$case2/bucket/mortar.json")
assert "missing-asc-leaves-manifest" [ "$after" = "$before" ]

# A bad signature must not rewrite hashes.
case3=$work/case-badsig
setup_tree "$case3"
export FIXTURE_DIR="$work/sums-bad"
install -d "$FIXTURE_DIR"
cp "$work/sums/SHA256SUMS" "$FIXTURE_DIR/SHA256SUMS"
printf 'not a signature\n' >"$FIXTURE_DIR/SHA256SUMS.asc"
if run_update "$case3" >/dev/null 2>"$work/case3.err"; then
  assert "badsig-exits" false
else
  assert "badsig-exits" true
fi
assert "badsig-mentions-key" grep -q "$fpr" "$work/case3.err"
after=$(jq -c '{version, architecture}' "$case3/bucket/mortar.json")
assert "badsig-leaves-manifest" [ "$after" = "$before" ]

# SUMS that omit an asset must name it.
case4=$work/case-empty
setup_tree "$case4"
export FIXTURE_DIR="$work/sums-empty"
install -d "$FIXTURE_DIR"
printf '%s  other.bin\n' "$amd" >"$FIXTURE_DIR/SHA256SUMS"
gpg --batch --yes --local-user "$fpr" --detach-sign --armor -o "$FIXTURE_DIR/SHA256SUMS.asc" "$FIXTURE_DIR/SHA256SUMS"
if run_update "$case4" >/dev/null 2>"$work/case4.err"; then
  assert "empty-hash-exits" false
else
  assert "empty-hash-exits" true
fi
assert "empty-hash-names-asset" grep -q mortar-windows-amd64.exe "$work/case4.err"

# A valid signature rewrites version and hashes.
case5=$work/case-ok
setup_tree "$case5"
export FIXTURE_DIR="$work/sums"
out=$(run_update "$case5")
assert "valid-prints-version" [ "$out" = "mortar 9.9.9" ]
assert "valid-version" [ "$(jq -r .version "$case5/bucket/mortar.json")" = "9.9.9" ]
assert "valid-amd" [ "$(jq -r '.architecture["64bit"].hash' "$case5/bucket/mortar.json")" = "$amd" ]
assert "valid-arm" [ "$(jq -r .architecture.arm64.hash "$case5/bucket/mortar.json")" = "$arm" ]
assert "valid-url" [ "$(jq -r '.architecture["64bit"].url' "$case5/bucket/mortar.json")" = "https://github.com/Rethunk-Tech/mortar/releases/download/v9.9.9/mortar-windows-amd64.exe#/mortar.exe" ]

exit "$fail"
