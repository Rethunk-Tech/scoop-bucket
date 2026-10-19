#!/usr/bin/env bash
# Point bucket/*.json at each tool's latest release. Hashes come from the checksum
# source named in the table (SHA256SUMS, or per-asset <file>.sha256). Mortar:
# SHA256SUMS.asc must VALIDSIG the Mortar packages key. Other tools: checksums
# fetched over HTTPS (no GPG). A tool with no matching Windows asset yet is skipped;
# Mortar missing SUMS/signature is fatal.
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd)
cd "$scripts/.."
FPR=D8B1C4C205C5FB3633CB8B9900B75959B637DCB5
# GitHub's /releases/latest redirect is public. The Actions token is this bucket's
# repo-scoped github.token and must not be sent to the upstream repos.
# HEAD stays unfollowed: -L would land on the tag page and empty %{redirect_url}.
curl_get() {
  curl --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 60 -fsSLo "$1" "$2"
}
sha256() { [[ $1 =~ ^[0-9a-fA-F]{64}$ ]]; }
hash_of() { awk -v f="$1" '$2 == f {print $1}' "$2"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

update_one() {
  local name=$1 repo=$2 trust=$3 amd_pat=$4 arm_pat=$5 bin=$6 homepage=$7 license=$8 desc=$9
  local latest tag version base amd_file arm_file sums amd arm
  local dest out u64 uarm notes gh

  if ! latest=$(timeout 30 curl --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 60 -fsSI -o /dev/null -w '%{redirect_url}' "https://github.com/$repo/releases/latest"); then
    if [ "$name" = mortar ]; then
      echo "error: could not read the latest Mortar release from GitHub" >&2
      exit 1
    fi
    echo "$name: no matching release" >&2
    return 0
  fi
  tag=${latest##*/}
  if [ -z "$tag" ] || [ "$tag" = "latest" ]; then
    if [ "$name" = mortar ]; then
      echo "error: latest Mortar release has an empty tag" >&2
      exit 1
    fi
    echo "$name: no matching release" >&2
    return 0
  fi
  if [[ ! $tag =~ ^v[0-9][0-9A-Za-z._-]*$ ]]; then
    if [ "$name" = mortar ]; then
      echo "error: latest Mortar release tag is not a v-prefixed version" >&2
      exit 1
    fi
    echo "$name: no matching release" >&2
    return 0
  fi
  version=${tag#v}
  if [ -z "$version" ]; then
    if [ "$name" = mortar ]; then
      echo "error: latest Mortar release has an empty tag" >&2
      exit 1
    fi
    echo "$name: no matching release" >&2
    return 0
  fi

  base="https://github.com/$repo/releases/download/$tag"
  amd_file=${amd_pat//\{VERSION\}/$version}
  arm_file=${arm_pat//\{VERSION\}/$version}
  install -d "$tmp/$name"
  sums="$tmp/$name/SHA256SUMS"

  if [ "$trust" = gpg ]; then
    [ -f "$scripts/mortar-archive-keyring.asc" ] || {
      echo "error: missing mortar-archive-keyring.asc" >&2
      exit 1
    }
    if ! curl_get "$sums" "$base/SHA256SUMS"; then
      echo "error: SHA256SUMS unavailable at $base/SHA256SUMS" >&2
      exit 1
    fi
    if ! curl_get "$tmp/$name/SHA256SUMS.asc" "$base/SHA256SUMS.asc"; then
      echo "error: SHA256SUMS.asc unavailable at $base/SHA256SUMS.asc" >&2
      exit 1
    fi
    export GNUPGHOME="$tmp/gnupg"
    install -d -m 700 "$GNUPGHOME"
    gpg --batch --quiet --import "$scripts/mortar-archive-keyring.asc"
    if ! gpg --batch --status-fd 1 --verify "$tmp/$name/SHA256SUMS.asc" "$sums" >"$tmp/$name/gpg.status" 2>/dev/null; then
      echo "error: SHA256SUMS is not signed by $FPR" >&2
      exit 1
    fi
    if ! grep -q "^\[GNUPG:\] VALIDSIG $FPR" "$tmp/$name/gpg.status"; then
      echo "error: SHA256SUMS is not signed by $FPR" >&2
      exit 1
    fi
    if grep -qE '^\[GNUPG:\] (REVKEYSIG|EXPKEYSIG) ' "$tmp/$name/gpg.status"; then
      echo "error: SHA256SUMS is not signed by $FPR" >&2
      exit 1
    fi
  elif [ "$trust" != per-asset ]; then
    if ! curl_get "$sums" "$base/SHA256SUMS"; then
      echo "$name: no matching release" >&2
      return 0
    fi
  fi

  if [ "$trust" = per-asset ]; then
    if ! curl_get "$tmp/$name/${amd_file}.sha256" "$base/${amd_file}.sha256"; then
      echo "$name: no matching release" >&2
      return 0
    fi
    amd=$(hash_of "$amd_file" "$tmp/$name/${amd_file}.sha256")
    if [ -z "$amd" ]; then
      echo "$name: no matching release" >&2
      return 0
    fi
    if ! sha256 "$amd"; then
      echo "error: hash for $amd_file is not 64 hex characters" >&2
      exit 1
    fi
    if [ -n "$arm_file" ]; then
      if ! curl_get "$tmp/$name/${arm_file}.sha256" "$base/${arm_file}.sha256"; then
        echo "$name: no matching release" >&2
        return 0
      fi
      arm=$(hash_of "$arm_file" "$tmp/$name/${arm_file}.sha256")
      if [ -z "$arm" ]; then
        echo "$name: no matching release" >&2
        return 0
      fi
      if ! sha256 "$arm"; then
        echo "error: hash for $arm_file is not 64 hex characters" >&2
        exit 1
      fi
    fi
  else
    amd=$(hash_of "$amd_file" "$sums")
    if [ -z "$amd" ]; then
      if [ "$trust" = gpg ]; then
        echo "error: SHA256SUMS has no hash for $amd_file" >&2
        exit 1
      fi
      echo "$name: no matching release" >&2
      return 0
    fi
    if ! sha256 "$amd"; then
      echo "error: SHA256SUMS hash for $amd_file is not 64 hex characters" >&2
      exit 1
    fi
    if [ -n "$arm_file" ]; then
      arm=$(hash_of "$arm_file" "$sums")
      if [ -z "$arm" ]; then
        if [ "$trust" = gpg ]; then
          echo "error: SHA256SUMS has no hash for $arm_file" >&2
          exit 1
        fi
        echo "$name: no matching release" >&2
        return 0
      fi
      if ! sha256 "$arm"; then
        echo "error: SHA256SUMS hash for $arm_file is not 64 hex characters" >&2
        exit 1
      fi
    fi
  fi

  dest="bucket/$name.json"
  u64="$base/$amd_file#/$bin"
  out="$tmp/$name.json"
  gh="https://github.com/$repo"
  if [ ! -f "$dest" ]; then
    if [ "$trust" = per-asset ]; then
      notes="Run 'scoop update $name' after this bucket updates. Hashes are pinned from each asset's .sha256 file fetched over HTTPS (not GPG-signed)."
    else
      notes="Run 'scoop update $name' after this bucket updates. Hashes are pinned from the release SHA256SUMS fetched over HTTPS (not GPG-signed)."
    fi
    if [ -n "$arm_file" ]; then
      uarm="$base/$arm_file#/$bin"
      jq -n --arg v "$version" --arg desc "$desc" --arg home "$homepage" --arg lic "$license" \
        --arg notes "$notes" --arg u64 "$u64" --arg amd "$amd" --arg uarm "$uarm" --arg arm "$arm" \
        --arg bin "$bin" --arg gh "$gh" '
        {
          version: $v,
          description: $desc,
          homepage: $home,
          license: $lic,
          notes: $notes,
          architecture: {
            "64bit": {url: $u64, hash: $amd},
            arm64: {url: $uarm, hash: $arm}
          },
          bin: $bin,
          checkver: {github: $gh}
        }' >"$out"
    else
      jq -n --arg v "$version" --arg desc "$desc" --arg home "$homepage" --arg lic "$license" \
        --arg notes "$notes" --arg u64 "$u64" --arg amd "$amd" --arg bin "$bin" --arg gh "$gh" '
        {
          version: $v,
          description: $desc,
          homepage: $home,
          license: $lic,
          notes: $notes,
          architecture: {
            "64bit": {url: $u64, hash: $amd}
          },
          bin: $bin,
          checkver: {github: $gh}
        }' >"$out"
    fi
  elif [ -n "$arm_file" ]; then
    uarm="$base/$arm_file#/$bin"
    jq --arg v "$version" --arg u64 "$u64" --arg amd "$amd" --arg uarm "$uarm" --arg arm "$arm" '
      .version = $v
      | .architecture["64bit"].url = $u64
      | .architecture["64bit"].hash = $amd
      | .architecture.arm64.url = $uarm
      | .architecture.arm64.hash = $arm' "$dest" >"$out"
  else
    jq --arg v "$version" --arg u64 "$u64" --arg amd "$amd" '
      .version = $v
      | .architecture["64bit"].url = $u64
      | .architecture["64bit"].hash = $amd' "$dest" >"$out"
  fi
  if cmp -s "$dest" "$out" 2>/dev/null; then
    echo "$name $version already current" >&2
    return 0
  fi
  mv "$out" "$dest"
  echo "$name $version"
}

# name|repo|trust|amd64-asset|arm64-asset|bin|homepage|license|description
# trust=gpg: VALIDSIG on SHA256SUMS. trust=sha256sums: SHA256SUMS over TLS.
# trust=per-asset: each <asset>.sha256 over TLS (no SHA256SUMS).
# {VERSION} in an asset name is the tag without the leading v.
# Windows Scoop: bare binaries, renamed via url #/bin. No Darwin/linux-only tools.
while IFS='|' read -r name repo trust amd_pat arm_pat bin homepage license desc; do
  [ -n "$name" ] || continue
  update_one "$name" "$repo" "$trust" "$amd_pat" "$arm_pat" "$bin" "$homepage" "$license" "$desc"
done <<'TABLE'
mortar|Rethunk-Tech/mortar|gpg|mortar-windows-amd64.exe|mortar-windows-arm64.exe|mortar.exe|https://mortar.rethunk.tech/|AGPL-3.0-only|Desktop mod manager for PC games: profiles, mod loader setup, Nexus Mods, GitHub and Thunderstore downloads, and shareable profiles
rgit|Rethunk-Tech/rethunk-git-cli|sha256sums|rgit-v{VERSION}-windows-amd64.exe||rgit.exe|https://github.com/Rethunk-Tech/rethunk-git-cli|MIT|Symbol-granular git staging and commits
gate|Rethunk-Tech/rethunk-gate-cli|sha256sums|gate-windows-amd64.exe||gate.exe|https://github.com/Rethunk-Tech/rethunk-gate-cli|MIT|Runs a project's gates concurrently, keeps every byte in a log
format-dispatch|Rethunk-Tech/claude-format-hooks|per-asset|format-dispatch-windows-amd64.exe||format-dispatch.exe|https://github.com/Rethunk-Tech/claude-format-hooks|MIT|Claude Code PostToolUse format/lint dispatcher hook
TABLE
