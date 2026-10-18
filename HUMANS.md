# HUMANS

Install: [README.md](README.md).

## Update

```powershell
scoop update mortar
scoop update rgit
scoop update gate
scoop update format-dispatch
```

Pins move only after this repo commits a new `bucket/*.json`. Scoop `checkver` can report a newer GitHub tag while the pins still match the last committed release.

## Uninstall

```powershell
scoop uninstall mortar
scoop uninstall rgit
scoop uninstall gate
scoop uninstall format-dispatch
scoop bucket rm mortar
```

## Maintainer bump

`scripts/update.sh` takes no flags. Needs `curl`, `gpg`, `jq`, and `timeout` on `PATH`:

```bash
scripts/update.sh
```

Each table entry's latest tag is the public `/releases/latest` redirect (30s). Success stdout: `<name> <version>` per rewritten manifest. Matching `SHA256SUMS` (Mortar: signed) writes `<name> <version> already current` to stderr and leaves that manifest unchanged. A tool whose latest release lacks `SHA256SUMS` or the expected Windows assets prints `<name>: no matching release` on stderr and writes no file.

Mortar: a missing, unsigned, or unreachable `SHA256SUMS` / `SHA256SUMS.asc` is fatal. Other tools: `SHA256SUMS` over HTTPS, hashes checked against that file (not GPG). HTTPS only, connect 15s, max 60s.

## Verify

```bash
make test
gate
```
