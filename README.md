<h1 align="center">Rethunk Scoop bucket</h1>

---

[Scoop](https://scoop.sh) manifests for Rethunk tools that ship a Windows amd64 release asset.

```powershell
scoop bucket add mortar https://github.com/Rethunk-Tech/scoop-bucket
scoop install mortar/mortar
scoop install mortar/rgit
scoop install mortar/gate
scoop install mortar/format-dispatch
```

| App | Upstream | Windows assets |
| --- | --- | --- |
| `mortar` | [Mortar](https://mortar.rethunk.tech/) | amd64, arm64 |
| `rgit` | [rethunk-git-cli](https://github.com/Rethunk-Tech/rethunk-git-cli) | amd64 |
| `gate` | [rethunk-gate-cli](https://github.com/Rethunk-Tech/rethunk-gate-cli) | amd64 |
| `format-dispatch` | [claude-format-hooks](https://github.com/Rethunk-Tech/claude-format-hooks) | amd64, arm64 |

heft and engined are Homebrew-only until they ship a `windows-amd64` asset.

**Trust model.** Pins come from each release's `SHA256SUMS` over HTTPS. Mortar also requires `VALIDSIG` for `D8B1 C4C2 05C5 FB36 33CB  8B99 00B7 5959 B637 DCB5` on `SHA256SUMS.asc`. The other tools publish unsigned `SHA256SUMS`; the updater fetches that file with HTTPS-only curl and pins the listed hashes. A tool with no matching release yet is skipped (no placeholder manifest).

Update, uninstall, maintainer bump: [HUMANS.md](HUMANS.md). Layout and invariants: [AGENTS.md](AGENTS.md). Work not built: [TODO.md](TODO.md).

Manifest license: AGPL-3.0-only for Mortar (same key as `bucket/mortar.json`); MIT for the CLI tools.
