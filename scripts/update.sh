#!/usr/bin/env bash
# Point bucket/mortar.json at Mortar's latest release. Hashes come from the release's SHA256SUMS, whose GPG signature is
# checked against the Mortar packages key; a release without SHA256SUMS is hashed by downloading its files.
set -euo pipefail
cd "$(dirname "$0")/.."
FPR=D8B1C4C205C5FB3633CB8B9900B75959B637DCB5
tag=$(gh release view --repo Rethunk-Tech/mortar --json tagName --jq .tagName)
version=${tag#v}
[ "$(jq -r .version bucket/mortar.json)" != "$version" ] || exit 0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
base="https://github.com/Rethunk-Tech/mortar/releases/download/$tag"
if curl -fsLo "$tmp/SHA256SUMS" "$base/SHA256SUMS"; then
  curl -fsSLo "$tmp/SHA256SUMS.asc" "$base/SHA256SUMS.asc"
  export GNUPGHOME="$tmp/gnupg"
  install -d -m 700 "$GNUPGHOME"
  curl -fsSL https://mortar.rethunk.tech/packages/mortar-archive-keyring.asc | gpg --batch --quiet --import
  gpg --batch --status-fd 1 --verify "$tmp/SHA256SUMS.asc" "$tmp/SHA256SUMS" 2>/dev/null | grep -q "VALIDSIG $FPR"
  hash() { awk -v f="$1" '$2 == f {print $1}' "$tmp/SHA256SUMS"; }
else
  hash() { curl -fsSL "$base/$1" | sha256sum | cut -d' ' -f1; }
fi
amd=$(hash mortar-windows-amd64.exe)
arm=$(hash mortar-windows-arm64.exe)
[ -n "$amd" ] && [ -n "$arm" ]
jq --arg v "$version" --arg base "$base" --arg amd "$amd" --arg arm "$arm" '
  .version = $v
  | .architecture["64bit"].url = "\($base)/mortar-windows-amd64.exe#/mortar.exe"
  | .architecture["64bit"].hash = $amd
  | .architecture.arm64.url = "\($base)/mortar-windows-arm64.exe#/mortar.exe"
  | .architecture.arm64.hash = $arm' bucket/mortar.json >"$tmp/mortar.json"
mv "$tmp/mortar.json" bucket/mortar.json
echo "mortar $version"
