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
| `format-dispatch` | [claude-format-hooks](https://github.com/Rethunk-Tech/claude-format-hooks) | amd64 |

heft and engined are omitted: they ship Linux-only assets (engined is a Bun app tree, not a native binary).

**Trust model.** Mortar pins from signed `SHA256SUMS` (`VALIDSIG` for `D8B1 C4C2 05C5 FB36 33CB  8B99 00B7 5959 B637 DCB5` on `SHA256SUMS.asc`). `rgit` and `gate` pin from unsigned `SHA256SUMS` over HTTPS. `format-dispatch` pins from each asset's `.sha256` file (no `SHA256SUMS`). A tool with no matching release yet is skipped (no placeholder manifest).

Update, uninstall, maintainer bump: [HUMANS.md](HUMANS.md). Layout and invariants: [AGENTS.md](AGENTS.md). Work not built: [TODO.md](TODO.md).

Manifest license: AGPL-3.0-only for Mortar (same key as `bucket/mortar.json`); MIT for the CLI tools.
