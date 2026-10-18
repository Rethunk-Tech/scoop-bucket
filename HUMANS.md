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

`scripts/update.sh` takes no flags and prints no `--help`. From the repo root, with `curl`, `gpg`, `jq`, and `timeout` on `PATH`:

```bash
scripts/update.sh
```

The latest [Rethunk-Tech/mortar](https://github.com/Rethunk-Tech/mortar) tag is the public `/releases/latest` redirect (30s timeout). On success stdout is `mortar <version>`. If version, URLs, and hashes already match the signed `SHA256SUMS`, the script exits 0, writes `mortar <version> already current` to stderr, and leaves the manifest bytes unchanged.

A missing, unsigned, or unreachable `SHA256SUMS` / `SHA256SUMS.asc` is fatal. Downloads use HTTPS only, connect timeout 15s, max time 60s.

Schedule: `.github/workflows/update.yml` cron `17 */6 * * *` plus `workflow_dispatch`. The job runs `scripts/update.sh` and commits only `bucket/mortar.json` when that file changed.

## Verify

```bash
make test
gate
```

`make test` runs `scripts/update.test.sh`.
