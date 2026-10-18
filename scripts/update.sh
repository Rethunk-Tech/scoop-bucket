#!/usr/bin/env bash
# Point bucket/mortar.json at Mortar's latest release. Hashes come from the release's SHA256SUMS, whose GPG signature is
# checked against the Mortar packages key. A missing, unsigned, or unreachable SHA256SUMS is fatal.
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd)
cd "$scripts/.."
FPR=D8B1C4C205C5FB3633CB8B9900B75959B637DCB5
if ! tag=$(timeout 30 gh release view --repo Rethunk-Tech/mortar --json tagName --jq .tagName); then
  echo "error: could not read the latest Mortar release from GitHub" >&2
  exit 1
fi
[[ $tag =~ ^v[0-9][0-9A-Za-z._-]*$ ]] || {
  echo "error: latest Mortar release tag is not a v-prefixed version" >&2
  exit 1
}
version=${tag#v}
[ -n "$version" ] || {
  echo "error: latest Mortar release has an empty tag" >&2
  exit 1
}
if [ "$(jq -r .version bucket/mortar.json)" = "$version" ]; then
  echo "mortar $version already current" >&2
  exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
base="https://github.com/Rethunk-Tech/mortar/releases/download/$tag"
[ -f "$scripts/mortar-archive-keyring.asc" ] || {
  echo "error: missing mortar-archive-keyring.asc" >&2
  exit 1
}
curl_get() {
  curl --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 60 -fsSLo "$1" "$2"
}
if ! curl_get "$tmp/SHA256SUMS" "$base/SHA256SUMS"; then
  echo "error: SHA256SUMS unavailable at $base/SHA256SUMS" >&2
  exit 1
fi
if ! curl_get "$tmp/SHA256SUMS.asc" "$base/SHA256SUMS.asc"; then
  echo "error: SHA256SUMS.asc unavailable at $base/SHA256SUMS.asc" >&2
  exit 1
fi
export GNUPGHOME="$tmp/gnupg"
install -d -m 700 "$GNUPGHOME"
gpg --batch --quiet --import "$scripts/mortar-archive-keyring.asc"
gpg --batch --status-fd 1 --verify "$tmp/SHA256SUMS.asc" "$tmp/SHA256SUMS" >"$tmp/gpg.status" 2>/dev/null || true
if ! grep -q "VALIDSIG $FPR" "$tmp/gpg.status"; then
  echo "error: SHA256SUMS is not signed by $FPR" >&2
  exit 1
fi
hash() { awk -v f="$1" '$2 == f {print $1}' "$tmp/SHA256SUMS"; }
amd=$(hash mortar-windows-amd64.exe)
arm=$(hash mortar-windows-arm64.exe)
[ -n "$amd" ] || {
  echo "error: SHA256SUMS has no hash for mortar-windows-amd64.exe" >&2
  exit 1
}
[ -n "$arm" ] || {
  echo "error: SHA256SUMS has no hash for mortar-windows-arm64.exe" >&2
  exit 1
}
sha256() { [[ $1 =~ ^[0-9a-fA-F]{64}$ ]]; }
sha256 "$amd" || {
  echo "error: SHA256SUMS hash for mortar-windows-amd64.exe is not 64 hex characters" >&2
  exit 1
}
sha256 "$arm" || {
  echo "error: SHA256SUMS hash for mortar-windows-arm64.exe is not 64 hex characters" >&2
  exit 1
}
jq --arg v "$version" --arg base "$base" --arg amd "$amd" --arg arm "$arm" '
  .version = $v
  | .architecture["64bit"].url = "\($base)/mortar-windows-amd64.exe#/mortar.exe"
  | .architecture["64bit"].hash = $amd
  | .architecture.arm64.url = "\($base)/mortar-windows-arm64.exe#/mortar.exe"
  | .architecture.arm64.hash = $arm' bucket/mortar.json >"$tmp/mortar.json"
mv "$tmp/mortar.json" bucket/mortar.json
echo "mortar $version"
