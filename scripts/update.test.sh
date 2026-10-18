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
if [ -n "${CURL_ARGS_FILE-}" ]; then
  printf '%s\n' "$@" >"$CURL_ARGS_FILE"
fi
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
  env -u GNUPGHOME PATH="$PATH" FIXTURE_DIR="$FIXTURE_DIR" CURL_FAIL="${CURL_FAIL:-}" CURL_ARGS_FILE="${CURL_ARGS_FILE:-}" "$dest/scripts/update.sh"
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
export FIXTURE_DIR="$work/sums" CURL_ARGS_FILE="$work/curl.args"
out=$(run_update "$case5")
assert "valid-prints-version" [ "$out" = "mortar 9.9.9" ]
assert "valid-version" [ "$(jq -r .version "$case5/bucket/mortar.json")" = "9.9.9" ]
assert "valid-amd" [ "$(jq -r '.architecture["64bit"].hash' "$case5/bucket/mortar.json")" = "$amd" ]
assert "valid-arm" [ "$(jq -r .architecture.arm64.hash "$case5/bucket/mortar.json")" = "$arm" ]
assert "valid-url" [ "$(jq -r '.architecture["64bit"].url' "$case5/bucket/mortar.json")" = "https://github.com/Rethunk-Tech/mortar/releases/download/v9.9.9/mortar-windows-amd64.exe#/mortar.exe" ]
assert "curl-uses-max-time" grep -qx -- '--max-time' "$work/curl.args"
assert "curl-uses-connect-timeout" grep -qx -- '--connect-timeout' "$work/curl.args"
assert "curl-https-only" grep -qx -- '--proto' "$work/curl.args"
unset CURL_ARGS_FILE

# SUMS that list amd64 but omit arm64 must name the missing asset.
case6=$work/case-no-arm
setup_tree "$case6"
export FIXTURE_DIR="$work/sums-no-arm"
install -d "$FIXTURE_DIR"
printf '%s  mortar-windows-amd64.exe\n' "$amd" >"$FIXTURE_DIR/SHA256SUMS"
gpg --batch --yes --local-user "$fpr" --detach-sign --armor -o "$FIXTURE_DIR/SHA256SUMS.asc" "$FIXTURE_DIR/SHA256SUMS"
if run_update "$case6" >/dev/null 2>"$work/case6.err"; then
  assert "missing-arm-exits" false
else
  assert "missing-arm-exits" true
fi
assert "missing-arm-names-asset" grep -q mortar-windows-arm64.exe "$work/case6.err"
after=$(jq -c '{version, architecture}' "$case6/bucket/mortar.json")
assert "missing-arm-leaves-manifest" [ "$after" = "$before" ]

# gh release view failing must name GitHub, not fall through unsigned.
case7=$work/case-gh-fail
setup_tree "$case7"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$work/bin/gh"
export FIXTURE_DIR="$work/sums"
if run_update "$case7" >/dev/null 2>"$work/case7.err"; then
  assert "gh-fail-exits" false
else
  assert "gh-fail-exits" true
fi
assert "gh-fail-names-github" grep -q GitHub "$work/case7.err"
after=$(jq -c '{version, architecture}' "$case7/bucket/mortar.json")
assert "gh-fail-leaves-manifest" [ "$after" = "$before" ]

# An empty tag must not rewrite URLs to .../download/.
case8=$work/case-empty-tag
setup_tree "$case8"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '\n'
EOF
chmod +x "$work/bin/gh"
if run_update "$case8" >/dev/null 2>"$work/case8.err"; then
  assert "empty-tag-exits" false
else
  assert "empty-tag-exits" true
fi
assert "empty-tag-names-tag" grep -q tag "$work/case8.err"
after=$(jq -c '{version, architecture}' "$case8/bucket/mortar.json")
assert "empty-tag-leaves-manifest" [ "$after" = "$before" ]

# A missing packages keyring must name the file before gpg import.
case9=$work/case-no-keyring
setup_tree "$case9"
rm -f "$case9/scripts/mortar-archive-keyring.asc"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "v9.9.9"
EOF
chmod +x "$work/bin/gh"
export FIXTURE_DIR="$work/sums"
if run_update "$case9" >/dev/null 2>"$work/case9.err"; then
  assert "missing-keyring-exits" false
else
  assert "missing-keyring-exits" true
fi
assert "missing-keyring-names-file" grep -q 'error: missing mortar-archive-keyring.asc' "$work/case9.err"
after=$(jq -c '{version, architecture}' "$case9/bucket/mortar.json")
assert "missing-keyring-leaves-manifest" [ "$after" = "$before" ]

# A token that is not 64 hex chars must not become the pinned hash.
case11=$work/case-short-hash
setup_tree "$case11"
export FIXTURE_DIR="$work/sums-short"
install -d "$FIXTURE_DIR"
printf 'deadbeef  mortar-windows-amd64.exe\n%s  mortar-windows-arm64.exe\n' "$arm" >"$FIXTURE_DIR/SHA256SUMS"
gpg --batch --yes --local-user "$fpr" --detach-sign --armor -o "$FIXTURE_DIR/SHA256SUMS.asc" "$FIXTURE_DIR/SHA256SUMS"
if run_update "$case11" >/dev/null 2>"$work/case11.err"; then
  assert "short-hash-exits" false
else
  assert "short-hash-exits" true
fi
assert "short-hash-names-amd" grep -q mortar-windows-amd64.exe "$work/case11.err"
after=$(jq -c '{version, architecture}' "$case11/bucket/mortar.json")
assert "short-hash-leaves-manifest" [ "$after" = "$before" ]

# Already current must leave the manifest and say so on stderr.
case10=$work/case-current
setup_tree "$case10"
jq --arg v 9.9.9 '.version = $v' "$case10/bucket/mortar.json" >"$work/current.json"
mv "$work/current.json" "$case10/bucket/mortar.json"
before10=$(jq -c '{version, architecture}' "$case10/bucket/mortar.json")
export FIXTURE_DIR="$work/sums"
run_update "$case10" >"$work/case10.out" 2>"$work/case10.err"
assert "current-stdout-empty" [ ! -s "$work/case10.out" ]
assert "current-names-already" grep -q 'already current' "$work/case10.err"
after=$(jq -c '{version, architecture}' "$case10/bucket/mortar.json")
assert "current-leaves-manifest" [ "$after" = "$before10" ]

# A slash in the tag must not be interpolated into the download URL.
case12=$work/case-slash-tag
setup_tree "$case12"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo 'v9.9.9/../../evil'
EOF
chmod +x "$work/bin/gh"
export FIXTURE_DIR="$work/sums"
if run_update "$case12" >/dev/null 2>"$work/case12.err"; then
  assert "slash-tag-exits" false
else
  assert "slash-tag-exits" true
fi
assert "slash-tag-names-tag" grep -q 'v-prefixed version' "$work/case12.err"
after=$(jq -c '{version, architecture}' "$case12/bucket/mortar.json")
assert "slash-tag-leaves-manifest" [ "$after" = "$before" ]

exit "$fail"
