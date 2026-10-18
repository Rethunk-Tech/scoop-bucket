<h1 align="center">Mortar Scoop bucket</h1>

---

[Scoop](https://scoop.sh) manifests for [Mortar](https://mortar.rethunk.tech/), the desktop mod manager for PC games. This bucket ships one app: `mortar`, with 64-bit and arm64 Windows downloads whose SHA-256 pins come from that release's signed `SHA256SUMS`.

## Quick start

```powershell
scoop bucket add mortar https://github.com/Rethunk-Tech/scoop-bucket
scoop install mortar/mortar
```

Install, update, and maintainer bump steps: [HUMANS.md](HUMANS.md).

## Highlights

- Pins `mortar-windows-amd64.exe` and `mortar-windows-arm64.exe` as `mortar.exe` (`bin` and a Start Menu shortcut).
- Takes hashes from the release `SHA256SUMS` after `gpg` reports `VALIDSIG` for the Mortar packages key (`D8B1 C4C2 05C5 FB36 33CB  8B99 00B7 5959 B637 DCB5`).
- `scripts/update.sh` rewrites version, URLs, and hashes only; it takes no flags. The Update workflow runs it on a six-hour cron and on `workflow_dispatch`.
- The manifest has `checkver.github` and no `autoupdate`. Scoop can see a newer GitHub tag; it does not rewrite pins. A matching version still verifies `SHA256SUMS` and rewrites only if a URL or hash differs.

## Documentation

| Doc | Role |
| --- | --- |
| [HUMANS.md](HUMANS.md) | Install, update, uninstall, maintainer bump |
| [AGENTS.md](AGENTS.md) | Layout and invariants |
| [TODO.md](TODO.md) | Work that is decided but not built |

## License

Manifest license: AGPL-3.0-only (same key as `bucket/mortar.json`).
