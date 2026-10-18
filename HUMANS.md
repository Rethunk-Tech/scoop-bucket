# HUMANS

Install: [README.md](README.md).

## Update

```powershell
scoop update mortar
```

Pins move only after this repo commits a new `bucket/mortar.json`. Scoop `checkver` can report a newer GitHub tag while the pins still match the last committed release.

## Uninstall

```powershell
scoop uninstall mortar
scoop bucket rm mortar
```

## Maintainer bump

`scripts/update.sh` takes no flags. Needs `curl`, `gpg`, `jq`, and `timeout` on `PATH`:

```bash
scripts/update.sh
```

Latest tag is the public `/releases/latest` redirect (30s). Success stdout: `mortar <version>`. Matching signed `SHA256SUMS` exits 0, writes `mortar <version> already current` to stderr, and leaves the manifest unchanged.

A missing, unsigned, or unreachable `SHA256SUMS` / `SHA256SUMS.asc` is fatal. HTTPS only, connect 15s, max 60s.

## Verify

```bash
make test
gate
```
