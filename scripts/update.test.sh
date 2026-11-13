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
if [[ $url == */releases/latest ]]; then
  if [ "${CURL_FAIL-}" = "latest" ]; then
    exit 22
  fi
  printf '%s\n' "${CURL_REDIRECT_URL:-https://github.com/Rethunk-Tech/mortar/releases/tag/v9.9.9}"
  exit 0
fi
file=${url##*/}
gh_repo=""
if [[ $url =~ github.com/[^/]+/([^/]+)/ ]]; then
  gh_repo=${BASH_REMATCH[1]}
fi
src=""
if [ -n "$gh_repo" ] && [ -f "${FIXTURE_DIR}/${gh_repo}/${file}" ]; then
  src="${FIXTURE_DIR}/${gh_repo}/${file}"
elif [ -f "${FIXTURE_DIR}/${file}" ]; then
  src="${FIXTURE_DIR}/${file}"
fi
if [ "${CURL_FAIL-}" = "$file" ]; then
  exit 22
fi
if [ -z "$src" ]; then
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
  cp "$repo/scripts/verify-sums.sh" "$dest/scripts/verify-sums.sh"
  cp "$work/throwaway.asc" "$dest/scripts/mortar-archive-keyring.asc"
}

run_update() {
  local dest=$1
  env -u GNUPGHOME PATH="$PATH" FIXTURE_DIR="$FIXTURE_DIR" CURL_FAIL="${CURL_FAIL:-}" CURL_ARGS_FILE="${CURL_ARGS_FILE:-}" CURL_REDIRECT_URL="${CURL_REDIRECT_URL:-}" RELEASE_UPDATE_FPR="${RELEASE_UPDATE_FPR:-}" RELEASE_UPDATE_KEYRING="${RELEASE_UPDATE_KEYRING:-}" "$dest/scripts/update.sh"
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
after=$(jq -c '{version, architecture}' "$case4/bucket/mortar.json")
assert "empty-hash-leaves-manifest" [ "$after" = "$before" ]

# A valid signature rewrites version and hashes.
case5=$work/case-ok
setup_tree "$case5"
export FIXTURE_DIR="$work/sums" CURL_ARGS_FILE="$work/curl.args"
out=$(run_update "$case5" 2>"$work/case5.err")
assert "valid-prints-version" [ "$out" = "mortar 9.9.9" ]
assert "valid-version" [ "$(jq -r .version "$case5/bucket/mortar.json")" = "9.9.9" ]
assert "valid-amd" [ "$(jq -r '.architecture["64bit"].hash' "$case5/bucket/mortar.json")" = "$amd" ]
assert "valid-arm" [ "$(jq -r .architecture.arm64.hash "$case5/bucket/mortar.json")" = "$arm" ]
assert "valid-url" [ "$(jq -r '.architecture["64bit"].url' "$case5/bucket/mortar.json")" = "https://github.com/Rethunk-Tech/mortar/releases/download/v9.9.9/mortar-windows-amd64.exe#/mortar.exe" ]
assert "curl-uses-max-time" grep -qx -- '--max-time' "$work/curl.args"
assert "curl-uses-connect-timeout" grep -qx -- '--connect-timeout' "$work/curl.args"
assert "curl-https-only" grep -qx -- '--proto' "$work/curl.args"
assert "curl-uses-retry" grep -qx -- '--retry' "$work/curl.args"
assert "curl-retry-count" [ "$(grep -A1 -x -- '--retry' "$work/curl.args" | tail -1)" = 18 ]
assert "curl-uses-retry-delay" grep -qx -- '--retry-delay' "$work/curl.args"
assert "curl-retry-delay-10" [ "$(grep -A1 -x -- '--retry-delay' "$work/curl.args" | tail -1)" = 10 ]
unset CURL_ARGS_FILE

# A validly signed release older than the pinned one (an old release re-marked latest) must not roll the pin back.
case_rb=$work/case-rollback
setup_tree "$case_rb"
export FIXTURE_DIR="$work/sums" CURL_REDIRECT_URL="https://github.com/Rethunk-Tech/mortar/releases/tag/v0.0.1"
if run_update "$case_rb" >/dev/null 2>"$work/case-rb.err"; then
  assert "rollback-exits-zero" true
else
  assert "rollback-exits-zero" false
fi
assert "rollback-says-older" grep -q 'mortar: latest 0.0.1 is older than pinned' "$work/case-rb.err"
after=$(jq -c '{version, architecture}' "$case_rb/bucket/mortar.json")
assert "rollback-leaves-manifest" [ "$after" = "$before" ]
unset CURL_REDIRECT_URL

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

# A failed latest-tag lookup must name GitHub, not fall through unsigned.
case7=$work/case-latest-fail
setup_tree "$case7"
export FIXTURE_DIR="$work/sums" CURL_FAIL=latest CURL_ARGS_FILE="$work/latest.args"
if run_update "$case7" >/dev/null 2>"$work/case7.err"; then
  assert "latest-fail-exits" false
else
  assert "latest-fail-exits" true
fi
assert "latest-fail-names-github" grep -q GitHub "$work/case7.err"
assert "latest-fetch-uses-retry" grep -qx -- '--retry' "$work/latest.args"
assert "latest-fetch-retry-count" [ "$(grep -A1 -x -- '--retry' "$work/latest.args" | tail -1)" = 18 ]
assert "latest-fetch-uses-retry-delay" grep -qx -- '--retry-delay' "$work/latest.args"
assert "latest-fetch-retry-delay-10" [ "$(grep -A1 -x -- '--retry-delay' "$work/latest.args" | tail -1)" = 10 ]
after=$(jq -c '{version, architecture}' "$case7/bucket/mortar.json")
assert "latest-fail-leaves-manifest" [ "$after" = "$before" ]
unset CURL_FAIL CURL_ARGS_FILE

# An empty tag must not rewrite URLs to .../download/.
case8=$work/case-empty-tag
setup_tree "$case8"
export CURL_REDIRECT_URL="https://github.com/Rethunk-Tech/mortar/releases/latest"
if run_update "$case8" >/dev/null 2>"$work/case8.err"; then
  assert "empty-tag-exits" false
else
  assert "empty-tag-exits" true
fi
assert "empty-tag-names-tag" grep -q tag "$work/case8.err"
after=$(jq -c '{version, architecture}' "$case8/bucket/mortar.json")
assert "empty-tag-leaves-manifest" [ "$after" = "$before" ]
unset CURL_REDIRECT_URL

# A missing packages keyring must name the file before gpg import.
case9=$work/case-no-keyring
setup_tree "$case9"
rm -f "$case9/scripts/mortar-archive-keyring.asc"
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
jq --arg v 9.9.9 --arg amd "$amd" --arg arm "$arm" --arg base "https://github.com/Rethunk-Tech/mortar/releases/download/v9.9.9" '
  .version = $v
  | .architecture["64bit"].url = "\($base)/mortar-windows-amd64.exe#/mortar.exe"
  | .architecture["64bit"].hash = $amd
  | .architecture.arm64.url = "\($base)/mortar-windows-arm64.exe#/mortar.exe"
  | .architecture.arm64.hash = $arm' "$case10/bucket/mortar.json" >"$work/current.json"
mv "$work/current.json" "$case10/bucket/mortar.json"
before10=$(jq -c '{version, architecture}' "$case10/bucket/mortar.json")
export FIXTURE_DIR="$work/sums"
run_update "$case10" >"$work/case10.out" 2>"$work/case10.err"
assert "current-stdout-empty" [ ! -s "$work/case10.out" ]
assert "current-names-already" grep -q 'already current' "$work/case10.err"
after=$(jq -c '{version, architecture}' "$case10/bucket/mortar.json")
assert "current-leaves-manifest" [ "$after" = "$before10" ]

# Matching version with a wrong hash must verify SUMS and rewrite the pin.
case13=$work/case-wrong-hash
setup_tree "$case13"
jq --arg v 9.9.9 --arg amd "$amd" --arg arm "$arm" --arg base "https://github.com/Rethunk-Tech/mortar/releases/download/v9.9.9" '
  .version = $v
  | .architecture["64bit"].url = "\($base)/mortar-windows-amd64.exe#/mortar.exe"
  | .architecture["64bit"].hash = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  | .architecture.arm64.url = "\($base)/mortar-windows-arm64.exe#/mortar.exe"
  | .architecture.arm64.hash = $arm' "$case13/bucket/mortar.json" >"$work/wrong-hash.json"
mv "$work/wrong-hash.json" "$case13/bucket/mortar.json"
export FIXTURE_DIR="$work/sums"
out=$(run_update "$case13" 2>"$work/case13.err")
assert "wrong-hash-prints-version" [ "$out" = "mortar 9.9.9" ]
if grep -q 'already current' "$work/case13.err"; then
  assert "wrong-hash-not-already" false
else
  assert "wrong-hash-not-already" true
fi
assert "wrong-hash-repairs-amd" [ "$(jq -r '.architecture["64bit"].hash' "$case13/bucket/mortar.json")" = "$amd" ]
assert "wrong-hash-keeps-version" [ "$(jq -r .version "$case13/bucket/mortar.json")" = "9.9.9" ]

# A slash in the tag must not be interpolated into the download URL.
case12=$work/case-slash-tag
setup_tree "$case12"
export CURL_REDIRECT_URL="https://github.com/Rethunk-Tech/mortar/releases/tag/v9.9.9/../../evil"
export FIXTURE_DIR="$work/sums"
if run_update "$case12" >/dev/null 2>"$work/case12.err"; then
  assert "slash-tag-exits" false
else
  assert "slash-tag-exits" true
fi
assert "slash-tag-names-tag" grep -q 'v-prefixed version' "$work/case12.err"
after=$(jq -c '{version, architecture}' "$case12/bucket/mortar.json")
assert "slash-tag-leaves-manifest" [ "$after" = "$before" ]
unset CURL_REDIRECT_URL

# Docs must not claim an updater-off marker this manifest does not set.
doc_absent() {
  local name=$1 file=$2
  if grep -qi 'updater stays off' "$file"; then
    assert "$name" false
  else
    assert "$name" true
  fi
}
if jq -e 'has("env_set") or has("pre_install") or has("post_install")' "$repo/bucket/mortar.json" >/dev/null; then
  assert "updater-hook-present" true
else
  doc_absent "notes-no-false-updater" "$repo/bucket/mortar.json"
  doc_absent "readme-no-false-updater" "$repo/README.md"
  doc_absent "humans-no-false-updater" "$repo/HUMANS.md"
fi
code_fpr=$(awk -F= '/^FPR=/{print $2}' "$repo/scripts/update.sh")
assert "readme-fpr-matches-update" grep -q "$code_fpr" <(tr -d ' \n' <"$repo/README.md")
assert "humans-names-update-script" grep -q 'scripts/update.sh' "$repo/HUMANS.md"
if grep -Eq 'update\.sh[[:space:]]+--' "$repo/HUMANS.md"; then
  assert "humans-no-update-sh-flags" false
else
  assert "humans-no-update-sh-flags" true
fi
if jq -e 'has("autoupdate")' "$repo/bucket/mortar.json" >/dev/null; then
  assert "manifest-has-no-autoupdate" false
else
  assert "manifest-has-no-autoupdate" true
fi

table_body() {
  awk '/^done <<'\''TABLE'\''$/{p=1;next} /^TABLE$/{exit} p' "$repo/scripts/update.sh"
}

n=$(table_body | grep -c . || true)
assert "table-row-count" [ "$n" = 4 ]
if table_body | grep -q '^heft|'; then
  assert "table-omits-heft" false
else
  assert "table-omits-heft" true
fi
if table_body | grep -q '^engined|'; then
  assert "table-omits-engined" false
else
  assert "table-omits-engined" true
fi
mortar_row=$(table_body | awk -F'|' '$1=="mortar"{print $2 "|" $3 "|" $4 "|" $5}')
assert "table-mortar-row" [ "$mortar_row" = "Rethunk-Tech/mortar|gpg|mortar-windows-amd64.exe|mortar-windows-arm64.exe" ]
rgit_row=$(table_body | awk -F'|' '$1=="rgit"{print $2 "|" $3 "|" $4 "|" $5}')
assert "table-rgit-row" [ "$rgit_row" = "Rethunk-Tech/rethunk-git-cli|gpgsums|rgit-v{VERSION}-windows-amd64.exe|" ]
gate_row=$(table_body | awk -F'|' '$1=="gate"{print $2 "|" $3 "|" $4}')
assert "table-gate-row" [ "$gate_row" = "Rethunk-Tech/rethunk-gate-cli|gpgsums|gate-windows-amd64.exe" ]
fd_row=$(table_body | awk -F'|' '$1=="format-dispatch"{print $2 "|" $3 "|" $4 "|" $5}')
assert "table-format-dispatch-row" [ "$fd_row" = "Rethunk-Tech/claude-format-hooks|gpgsums|format-dispatch-windows-amd64.exe|" ]

assert "skip-names-rgit" grep -q 'rgit: no matching release' "$work/case5.err"
assert "skip-names-gate" grep -q 'gate: no matching release' "$work/case5.err"
assert "skip-names-format-dispatch" grep -q 'format-dispatch: no matching release' "$work/case5.err"
assert "skip-no-rgit-json" [ ! -e "$case5/bucket/rgit.json" ]
assert "skip-no-gate-json" [ ! -e "$case5/bucket/gate.json" ]
assert "skip-no-format-dispatch-json" [ ! -e "$case5/bucket/format-dispatch.json" ]

wrong_home_pre=$work/wrong-pre
install -d -m 700 "$wrong_home_pre"
GNUPGHOME=$wrong_home_pre gpg --batch --passphrase '' --quick-generate-key "scoop-bucket-wrongrel@example.com" ed25519 sign never
# Release-key signing for gpgsums tools: a throwaway key stands in for the Rethunk.Tech release key.
rel_home=$work/rel-keys
install -d -m 700 "$rel_home"
GNUPGHOME=$rel_home gpg --batch --passphrase '' --quick-generate-key "scoop-bucket-release@example.com" ed25519 sign never
rel_fpr=$(GNUPGHOME=$rel_home gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" {print $10; exit}')
GNUPGHOME=$rel_home gpg --batch --export --armor >"$work/rel.asc"
sign_rel() { GNUPGHOME=$rel_home gpg --batch --yes --local-user "$rel_fpr" --detach-sign --armor -o "$1.asc" "$1"; }
export RELEASE_UPDATE_FPR=$rel_fpr RELEASE_UPDATE_KEYRING=$work/rel.asc

# Fixture release with rgit's SHA256SUMS creates the manifest, then a later run updates it.
rgit_amd=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
install -d "$work/sums/rethunk-git-cli"
printf '%s  rgit-v9.9.9-windows-amd64.exe\n' "$rgit_amd" >"$work/sums/rethunk-git-cli/SHA256SUMS"
sign_rel "$work/sums/rethunk-git-cli/SHA256SUMS"
case_create=$work/case-create
setup_tree "$case_create"
export FIXTURE_DIR="$work/sums"
out=$(run_update "$case_create" 2>"$work/create.err")
assert "create-prints-rgit" grep -qx 'rgit 9.9.9' <<<"$out"
assert "create-rgit-version" [ "$(jq -r .version "$case_create/bucket/rgit.json")" = "9.9.9" ]
assert "create-rgit-hash" [ "$(jq -r '.architecture["64bit"].hash' "$case_create/bucket/rgit.json")" = "$rgit_amd" ]
assert "create-rgit-url" [ "$(jq -r '.architecture["64bit"].url' "$case_create/bucket/rgit.json")" = "https://github.com/Rethunk-Tech/rethunk-git-cli/releases/download/v9.9.9/rgit-v9.9.9-windows-amd64.exe#/rgit.exe" ]
assert "create-rgit-bin" [ "$(jq -r .bin "$case_create/bucket/rgit.json")" = "rgit.exe" ]
if jq -e 'has("autoupdate")' "$case_create/bucket/rgit.json" >/dev/null; then
  assert "create-rgit-no-autoupdate" false
else
  assert "create-rgit-no-autoupdate" true
fi
assert "create-still-skips-gate" [ ! -e "$case_create/bucket/gate.json" ]
if grep -q 'release signing key' "$case_create/bucket/rgit.json"; then
  assert "create-rgit-https-notes" true
else
  assert "create-rgit-https-notes" false
fi

jq '.version = "0.0.1" | .architecture["64bit"].hash = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" | .notes = "stale (not GPG-signed)"' \
  "$case_create/bucket/rgit.json" >"$work/rgit-wrong.json"
mv "$work/rgit-wrong.json" "$case_create/bucket/rgit.json"
out=$(run_update "$case_create" 2>"$work/upd2.err")
assert "update-prints-rgit" grep -qx 'rgit 9.9.9' <<<"$out"
assert "update-rewrites-notes-from-mode" grep -q 'release signing key' <(jq -r .notes "$case_create/bucket/rgit.json")
assert "update-repairs-rgit" [ "$(jq -r '.architecture["64bit"].hash' "$case_create/bucket/rgit.json")" = "$rgit_amd" ]
if grep -q 'already current' <<<"$(grep rgit "$work/upd2.err" || true)"; then
  assert "update-rgit-not-already" false
else
  assert "update-rgit-not-already" true
fi

# Cut-over: a manifest already at the latest version (released before signing) is left alone even with no signature.
jq '.architecture["64bit"].hash = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
  "$case_create/bucket/rgit.json" >"$work/rgit-pinned.json"
mv "$work/rgit-pinned.json" "$case_create/bucket/rgit.json"
rm -f "$work/sums/rethunk-git-cli/SHA256SUMS.asc"
if run_update "$case_create" >/dev/null 2>"$work/cut.err"; then
  assert "cutover-current-unsigned-ok" true
else
  assert "cutover-current-unsigned-ok" false
fi
assert "cutover-leaves-manifest" [ "$(jq -r '.architecture["64bit"].hash' "$case_create/bucket/rgit.json")" = ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff ]

# A newer release with no signature, or one from another key, is refused and the manifest stays.
jq '.version = "0.0.1"' "$case_create/bucket/rgit.json" >"$work/rgit-old.json"
mv "$work/rgit-old.json" "$case_create/bucket/rgit.json"
if run_update "$case_create" >/dev/null 2>"$work/unsigned.err"; then
  assert "unsigned-new-release-exits" false
else
  assert "unsigned-new-release-exits" true
fi
assert "unsigned-new-release-names-fpr" grep -q "$rel_fpr" "$work/unsigned.err"
assert "unsigned-new-release-leaves-manifest" [ "$(jq -r .version "$case_create/bucket/rgit.json")" = 0.0.1 ]
GNUPGHOME=$wrong_home_pre gpg --batch --yes --detach-sign --armor -o "$work/sums/rethunk-git-cli/SHA256SUMS.asc" "$work/sums/rethunk-git-cli/SHA256SUMS"
if run_update "$case_create" >/dev/null 2>"$work/wrongrel.err"; then
  assert "wrong-key-new-release-exits" false
else
  assert "wrong-key-new-release-exits" true
fi
assert "wrong-key-new-release-leaves-manifest" [ "$(jq -r .version "$case_create/bucket/rgit.json")" = 0.0.1 ]
sign_rel "$work/sums/rethunk-git-cli/SHA256SUMS"

# format-dispatch pins from the signed SHA256SUMS; hash_of must bind $2 to the asset name.
fd_amd=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
fd_decoy=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
install -d "$work/sums/claude-format-hooks"
printf '%s  ignored.bin\n%s  format-dispatch-windows-amd64.exe\n' "$fd_decoy" "$fd_amd" >"$work/sums/claude-format-hooks/SHA256SUMS"
sign_rel "$work/sums/claude-format-hooks/SHA256SUMS"
case_fd=$work/case-fd
setup_tree "$case_fd"
export FIXTURE_DIR="$work/sums"
out=$(run_update "$case_fd" 2>"$work/fd.err")
assert "create-prints-format-dispatch" grep -qx 'format-dispatch 9.9.9' <<<"$out"
assert "create-fd-hash-from-sums" [ "$(jq -r '.architecture["64bit"].hash' "$case_fd/bucket/format-dispatch.json")" = "$fd_amd" ]
assert "create-fd-url" [ "$(jq -r '.architecture["64bit"].url' "$case_fd/bucket/format-dispatch.json")" = "https://github.com/Rethunk-Tech/claude-format-hooks/releases/download/v9.9.9/format-dispatch-windows-amd64.exe#/format-dispatch.exe" ]
assert "create-fd-bin" [ "$(jq -r .bin "$case_fd/bucket/format-dispatch.json")" = "format-dispatch.exe" ]
if jq -e '.architecture | has("arm64")' "$case_fd/bucket/format-dispatch.json" >/dev/null; then
  assert "create-fd-no-arm64" false
else
  assert "create-fd-no-arm64" true
fi
if grep -q 'release signing key' "$case_fd/bucket/format-dispatch.json"; then
  assert "create-fd-sidecar-notes" true
else
  assert "create-fd-sidecar-notes" false
fi

# A revoked packages key still yields VALIDSIG; the updater must not pin.
rev=$(ls "$work/keys/openpgp-revocs.d/"*.rev)
sed 's/^:\(-----BEGIN PGP PUBLIC KEY BLOCK-----\)/\1/' "$rev" | gpg --batch --import
gpg --batch --export --armor >"$work/throwaway-revoked.asc"
case_rev=$work/case-revoked
setup_tree "$case_rev"
cp "$work/throwaway-revoked.asc" "$case_rev/scripts/mortar-archive-keyring.asc"
export FIXTURE_DIR="$work/sums"
if run_update "$case_rev" >/dev/null 2>"$work/case-rev.err"; then
  assert "revoked-key-exits" false
else
  assert "revoked-key-exits" true
fi
assert "revoked-key-mentions-fpr" grep -q "$fpr" "$work/case-rev.err"
after=$(jq -c '{version, architecture}' "$case_rev/bucket/mortar.json")
assert "revoked-key-leaves-manifest" [ "$after" = "$before" ]
# gpg exits 0 and emits VALIDSIG for a signature from an expired key; update.sh must still refuse it.
exp_home=$work/exp-keys
install -d -m 700 "$exp_home"
GNUPGHOME=$exp_home gpg --batch --passphrase '' --faked-system-time 20200101T000000 --quick-generate-key "scoop-bucket-expired@example.com" default default 1d
exp_fpr=$(GNUPGHOME=$exp_home gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" {print $10; exit}')
GNUPGHOME=$exp_home gpg --batch --export --armor >"$work/expired.asc"
FIXTURE_DIR=$work/sums-expired
install -d "$FIXTURE_DIR"
cp "$work/sums/SHA256SUMS" "$FIXTURE_DIR/SHA256SUMS"
GNUPGHOME=$exp_home gpg --batch --yes --faked-system-time 20200101T120000 --local-user "$exp_fpr" --detach-sign --armor -o "$FIXTURE_DIR/SHA256SUMS.asc" "$FIXTURE_DIR/SHA256SUMS"
export FIXTURE_DIR
case_exp=$work/case-expired
setup_tree "$case_exp"
sed -i "s/$fpr/$exp_fpr/" "$case_exp/scripts/update.sh"
cp "$work/expired.asc" "$case_exp/scripts/mortar-archive-keyring.asc"
if run_update "$case_exp" >/dev/null 2>"$work/case-exp.err"; then
  assert "expired-key-exits" false
else
  assert "expired-key-exits" true
fi
assert "expired-key-mentions-fpr" grep -q "$exp_fpr" "$work/case-exp.err"
after=$(jq -c '{version, architecture}' "$case_exp/bucket/mortar.json")
assert "expired-key-leaves-manifest" [ "$after" = "$before" ]

# A valid signature from a key other than the pinned fingerprint must not pin.
wrong_home=$work/wrong-keys
install -d -m 700 "$wrong_home"
GNUPGHOME=$wrong_home gpg --batch --passphrase '' --quick-generate-key "scoop-bucket-wrong@example.com" default default never
wrong_fpr=$(GNUPGHOME=$wrong_home gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" {print $10; exit}')
GNUPGHOME=$wrong_home gpg --batch --export --armor >"$work/wrong.asc"
FIXTURE_DIR=$work/sums-wrongkey
install -d "$FIXTURE_DIR"
cp "$work/sums/SHA256SUMS" "$FIXTURE_DIR/SHA256SUMS"
GNUPGHOME=$wrong_home gpg --batch --yes --local-user "$wrong_fpr" --detach-sign --armor -o "$FIXTURE_DIR/SHA256SUMS.asc" "$FIXTURE_DIR/SHA256SUMS"
export FIXTURE_DIR
case_wrong=$work/case-wrong-key
setup_tree "$case_wrong"
cp "$work/wrong.asc" "$case_wrong/scripts/mortar-archive-keyring.asc"
if run_update "$case_wrong" >/dev/null 2>"$work/case-wrong.err"; then
  assert "wrong-key-exits" false
else
  assert "wrong-key-exits" true
fi
assert "wrong-key-mentions-pinned-fpr" grep -q "$fpr" "$work/case-wrong.err"
after=$(jq -c '{version, architecture}' "$case_wrong/bucket/mortar.json")
assert "wrong-key-leaves-manifest" [ "$after" = "$before" ]

# verify_sums guards the gpgsums tools: an expired or revoked key's VALIDSIG must not pass it either.
# shellcheck source=verify-sums.sh
. "$repo/scripts/verify-sums.sh"
if verify_sums "$work/sums-expired/SHA256SUMS" "$work/sums-expired/SHA256SUMS.asc" "$work/expired.asc" "$exp_fpr" "$work/vs-exp"; then
  assert "verify-sums-refuses-expired-key" false
else
  assert "verify-sums-refuses-expired-key" true
fi
if verify_sums "$work/sums/SHA256SUMS" "$work/sums/SHA256SUMS.asc" "$work/throwaway-revoked.asc" "$fpr" "$work/vs-rev"; then
  assert "verify-sums-refuses-revoked-key" false
else
  assert "verify-sums-refuses-revoked-key" true
fi

exit "$fail"
