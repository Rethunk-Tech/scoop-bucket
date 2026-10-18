# AGENTS

Layout and invariants for this Scoop bucket. Operator steps live in [HUMANS.md](HUMANS.md).

## Layout

| Path | Role |
| --- | --- |
| `bucket/mortar.json` | Scoop manifest: `version`, `architecture.64bit` / `arm64` `url`+`hash`, `bin`, `shortcuts`, `checkver.github`, `notes`. No `autoupdate`, `env_set`, `persist`, `pre_install`, or `post_install`. |
| `scripts/update.sh` | Bump writer. No flags, no usage text. Sets `GNUPGHOME` to a temp dir; does not read project env keys. |
| `scripts/mortar-archive-keyring.asc` | Mortar packages key. `FPR=D8B1C4C205C5FB3633CB8B9900B75959B637DCB5` must match `VALIDSIG`. |
| `scripts/update.test.sh` | Throwaway-keyring cases. Test-only env: `FIXTURE_DIR`, `CURL_FAIL`, `CURL_ARGS_FILE`, `CURL_REDIRECT_URL`. |
| `.github/workflows/update.yml` | `scripts/update.sh` → commit `bucket/mortar.json` when it differs. |
| `Makefile` | `make test` → `scripts/update.test.sh`. |

## Invariants

- `jq` assigns `.version`, `.architecture["64bit"].url`/`.hash`, and `.architecture.arm64.url`/`.hash` only. Other keys survive.
- URLs are `…/releases/download/<tag>/mortar-windows-{amd64,arm64}.exe#/mortar.exe`. Tags must match `^v[0-9][0-9A-Za-z._-]*$`.
- Version equality still fetches `SHA256SUMS` and requires `VALIDSIG`. The manifest is rewritten only when url or hash would change; matching bytes print `already current` on stderr and exit 0.
- `CLAUDE.md` is a symlink to this file; do not edit it as a separate document.
