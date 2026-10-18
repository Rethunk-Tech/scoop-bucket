# AGENTS

Operator steps: [HUMANS.md](HUMANS.md).

## Layout

| Path | Role |
| --- | --- |
| `bucket/*.json` | One Scoop manifest per packaged app. Mortar: `version`, `architecture.{64bit,arm64}` `url`+`hash`, `bin`, `shortcuts`, `checkver.github`, `notes`. No `autoupdate`, `env_set`, `persist`, `pre_install`, or `post_install`. |
| `scripts/update.sh` | No flags. Tool table at the `TABLE` heredoc (Scoop: mortar, rgit, gate, format-dispatch). `GNUPGHOME` is a temp dir; does not read project env keys. |
| `scripts/mortar-archive-keyring.asc` | `FPR=D8B1C4C205C5FB3633CB8B9900B75959B637DCB5` must match `VALIDSIG`. |
| `scripts/update.test.sh` | Test-only env: `FIXTURE_DIR`, `CURL_FAIL`, `CURL_ARGS_FILE`, `CURL_REDIRECT_URL`. |
| `.github/workflows/update.yml` | Runs `scripts/update.sh`; commits changed `bucket/*.json` when they differ. |

## Invariants

- On update, `jq` assigns `.version` and `.architecture["64bit"].url`/`.hash` (and `.architecture.arm64.url`/`.hash` when the table names an arm64 asset) only. Other keys survive. Missing manifests are created from the table when the latest release has the expected assets; otherwise the tool is skipped with an info line and no file is written.
- URLs are `…/releases/download/<tag>/<asset>#/<bin>`. Tags must match `^v[0-9][0-9A-Za-z._-]*$`. Mortar assets are `mortar-windows-{amd64,arm64}.exe`.
- Version equality still fetches `SHA256SUMS`. Mortar requires `VALIDSIG`. Other tools trust `SHA256SUMS` fetched over HTTPS and the hashes listed in it. Rewrite only when url or hash would change; matching bytes print `<name> <version> already current` on stderr and continue. Mortar missing, unsigned, or unreachable `SHA256SUMS` is fatal.
- `CLAUDE.md` is a symlink to this file; do not edit it as a separate document.
