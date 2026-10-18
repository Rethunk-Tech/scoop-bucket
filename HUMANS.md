# HUMANS

How to install Mortar from this bucket and how to bump the manifest.

## Quick start

```powershell
scoop bucket add mortar https://github.com/Rethunk-Tech/scoop-bucket
scoop install mortar/mortar
```

That installs `mortar.exe` on PATH and a Start Menu shortcut named Mortar.

## Update

```powershell
scoop update mortar
```

Pins move only after this repo's Update workflow (or a local `scripts/update.sh` run) commits a new `bucket/mortar.json`. `scoop update mortar` then installs those URLs and hashes. Scoop `checkver` can report a newer GitHub tag while the pinned hashes still match the last committed release.

## Uninstall

```powershell
scoop uninstall mortar
scoop bucket rm mortar
```

## Maintainer bump

`scripts/update.sh` takes no flags and prints no `--help`. From the repo root, with `gh`, `curl`, `gpg`, `jq`, and `timeout` on `PATH`:

```bash
scripts/update.sh
```

`gh release view` reads the latest [Rethunk-Tech/mortar](https://github.com/Rethunk-Tech/mortar) tag (30s timeout). `gh` uses `GH_TOKEN` or `GITHUB_TOKEN` when GitHub requires auth; the Update workflow sets `GH_TOKEN` to `github.token`. On success stdout is `mortar <version>`. If `bucket/mortar.json` already has that version, the script exits 0, writes `mortar <version> already current` to stderr, and does not fetch `SHA256SUMS`.

A missing, unsigned, or unreachable `SHA256SUMS` / `SHA256SUMS.asc` is fatal. Downloads use HTTPS only, connect timeout 15s, max time 60s.

Schedule: `.github/workflows/update.yml` cron `17 */6 * * *` plus `workflow_dispatch`. The job runs `scripts/update.sh` and commits only `bucket/mortar.json` when that file changed.

## Verify

```bash
make test
gate
```

`make test` runs `scripts/update.test.sh`.
