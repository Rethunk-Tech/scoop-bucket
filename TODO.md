# TODO

Work that is decided but not built. `README.md` describes what exists; this
file is the only place that describes what does not.

Sections are unordered.

## checkver has no autoupdate, so Scoop itself cannot bump hashes

`bucket/mortar.json` has `checkver.github` at `:25` and no `autoupdate` object.
`scoop status` can see a newer GitHub tag. `scoop update mortar` still
installs whatever this bucket last committed: URLs and SHA-256 pins only
move when `scripts/update.sh` rewrites the manifest after a GPG check of
`SHA256SUMS`. That split is deliberate. `dea4f99` dropped unsigned
`autoupdate` so Scoop would not fetch the exe and hash it itself.

A maintainer who runs `scoop update` inside this bucket, or a user whose
clone of the bucket is stale, sees a new version from `checkver` and no
safe way for Scoop to fill hashes. The scheduled workflow in
`.github/workflows/update.yml:20` is the only writer.

Decided shape: keep `checkver` as the version probe. Do not add Scoop
`autoupdate` that hashes `mortar-windows-*.exe` over HTTPS. If Scoop later
gains a way to take hashes from a signed `SHA256SUMS` (hashurl plus a
signature check, or a `pre_update` that calls this repo's script), wire
that here and drop the scheduled commit only after `scoop update` refuses
an unsigned SUMS the same way `update.sh:40` refuses a missing `VALIDSIG`.

Rejected: restoring `autoupdate` with `hash` downloaded from the exe. That
is the unsigned path `dea4f99` removed. Rejected: deleting `checkver`.
`scoop status` would go blind.

This leaves `scripts/update.sh` as the only hash writer and does not change
the install contract of `bucket/mortar.json`.

### Read

1. `bucket/mortar.json:24` `checkver` — GitHub tag probe, no sibling
   `autoupdate`.
2. `scripts/update.sh:40` `VALIDSIG $FPR` — the check Scoop autoupdate
   cannot perform today.
3. `.github/workflows/update.yml:20` — the six-hour writer that calls
   `scripts/update.sh`.
4. `README.md:10` — documents signed `SHA256SUMS` as the hash source.

### Traps

- **Scoop autoupdate hashes the binary, not the SUMS.** A `hash.url` that
  points at `SHA256SUMS` without verifying `SHA256SUMS.asc` is still
  unsigned input. The GPG check lives only in `update.sh`.
- **`checkver` staying is not a half-wire.** Pairing it with autoupdate is
  the usual Scoop shape. Here the missing half is the security boundary.
- **The workflow commit is the user-visible bump.** Removing it before
  Scoop can verify the signature leaves the bucket stuck on the last
  pushed version.

### Acceptance

- `bucket/mortar.json` still has `checkver.github` and still has no
  `autoupdate` that hashes the exe.
- `scripts/update.sh` still requires `VALIDSIG D8B1C4C205C5FB3633CB8B9900B75959B637DCB5`.
- `scoop update mortar` after a bucket pull still installs the pinned
  URLs and hashes from the manifest.
- `gate` stays green.

## notes claim Mortar's updater stays off, but the manifest sets no marker

`bucket/mortar.json:6` `notes` and `README.md:10` both say Mortar's own
updater stays off when Scoop installed it. The manifest has `bin` and
`shortcuts` only (`:17`, `:18`). There is no `env_set`, `persist`,
`pre_install`, or `post_install` that would tell Mortar it is Scoop-managed.

If Mortar keys off an environment variable, a file next to the exe, or
`SCOOP` already being set in a Scoop shell, the notes are documentation of
Mortar's behaviour and this section is a no-op once that is confirmed. If
Mortar looks for a marker this bucket never writes, the updater still
runs and races `scoop update`.

Decided shape: read Mortar's updater gate in the Mortar repo (not this
one). If it already treats a Scoop install as managed, leave the manifest
alone and tighten the notes to name the signal. If it expects a variable
or file, set that with `env_set` or a `post_install` that writes the
marker next to `mortar.exe`, and add `pre_uninstall` that removes only
that marker.

Rejected: guessing `MORTAR_NO_UPDATE=1` or writing a random `.scoop`
file. A wrong name is a silent miss. Rejected: disabling the updater by
shipping a patched exe.

### Read

1. `bucket/mortar.json:6` `notes` — the claim.
2. `README.md:10` — the same claim for humans.
3. `bucket/mortar.json:17` `bin` and `:18` `shortcuts` — the only
   install hooks today.

### Traps

- **The signal has to be the one Mortar already reads.** A new env var
  in this bucket does nothing until Mortar ships a reader.
- **`notes` are shown once.** They do not disable an updater. Changing
  the wording without a hook still leaves the race.
- **This workspace does not contain Mortar.** Confirm the gate there
  before editing the manifest.

### Acceptance

- After a `scoop install mortar`, Mortar's in-app updater does not offer
  or apply a self-replace. `scoop update mortar` remains the only bump.
- If the fix is a manifest hook, `bin` and `shortcuts` stay as they are
  and `scripts/update.sh` still only rewrites version, URLs, and hashes.
- If Mortar already detects Scoop, the notes name that detection and the
  manifest gains no unused key.
- `gate` stays green.

## a matching version skips SHA256SUMS, so a bad pin is never repaired

`scripts/update.sh:17` compares `bucket/mortar.json` `.version` to the
latest tag and exits 0 when they match. It does not fetch `SHA256SUMS`,
does not check `VALIDSIG`, and does not compare the pinned hashes. A
manifest that already says `0.3.0` but has a hand-edited or truncated
hash stays that way until Mortar cuts another release.

The no-op is what makes the scheduled workflow a no-commit when nothing
changed (`update.yml:23` `git diff --quiet`). Re-verifying every six
hours would rewrite the file whenever hashes were wrong, or no-op when
they already matched.

Decided shape: when the version matches, still download and verify
`SHA256SUMS`, then rewrite the manifest only if a URL or hash differs.
Keep stdout silent on a true no-op. Keep `mortar $version already current`
on stderr (`update.sh:18`). Do not bump a version that is already current.

Rejected: deleting the version short-circuit and always rewriting the
JSON. That produces a noisy `git diff` on key order or whitespace and
breaks `git diff --quiet && exit 0`. Rejected: failing the job when
hashes differ without rewriting. The workflow would stay red until a
human pasted hashes.

### Read

1. `scripts/update.sh:17` — the version equality exit.
2. `scripts/update.sh:40` — `VALIDSIG` on the SUMS, only reached after
   the version check.
3. `.github/workflows/update.yml:23` — commit skipped when the tree is
   clean.
4. `scripts/update.test.sh` `case10` — today's already-current fixture
   asserts the manifest is untouched and does not feed a mismatched hash.

### Traps

- **A rewrite must be byte-stable when pins already match.** `jq` that
   always writes will keep the workflow committing. Compare before `mv`.
- **`already current` stays on the true no-op.** A hash repair is not
   "already current"; print the same `mortar $version` stdout the bump
   path uses, or a dedicated repair line, and let git see the diff.
- **The existing already-current test must keep passing** for matching
   version and matching hashes. Add a case where version matches and
   amd64 hash does not.

### Acceptance

- Version matches and hashes match: exit 0, stderr `already current`,
  manifest bytes unchanged, workflow does not commit.
- Version matches and a hash or URL does not: SUMS must carry `VALIDSIG`,
  the pin is rewritten, exit 0, `git diff` is non-empty.
- Version matches and SUMS are missing, unsigned, or a hash is not 64
  hex: exit non-zero and leave the manifest, same as a bump failure.
- `scripts/update.test.sh` covers both the clean no-op and the hash
  repair. `gate` stays green.

## the manifest does not persist Mortar user data

`bucket/mortar.json` installs a single `mortar.exe` (`bin` at `:17`,
`shortcuts` at `:18`) and has no `persist` array. Scoop replaces the
app directory on every update. Profile data, tokens, or logs that Mortar
writes next to the exe, or under a path inside the app dir, disappear.

If Mortar already keeps state in `%APPDATA%` or another path outside the
Scoop app dir, persist is unnecessary. That location is decided in the
Mortar repo, which this workspace does not contain.

Decided shape: once Mortar's on-disk state directory is known, if and
only if it is under the app dir, add a `persist` entry for that relative
path. `scripts/update.sh` must keep copying the key through the `jq`
rewrite (it already preserves keys it does not assign). If state is
outside the app dir, record that here as not-applicable and add no key.

Rejected: persisting `*` or the whole app dir. That pins the exe and
fights Scoop's replace. Rejected: inventing `persist: ["data"]` before
Mortar writes that folder.

### Read

1. `bucket/mortar.json:17` `bin` and `:18` `shortcuts` — install surface,
   no `persist`.
2. `scripts/update.sh:64` `jq` — assigns version, URLs, and hashes only;
   other keys survive.

### Traps

- **Persist paths are relative to the app dir.** An absolute `%APPDATA%`
  path is the wrong field.
- **A guessed folder that Mortar never creates** shows up as an empty
  persist dir and does not save state.
- **This workspace cannot see Mortar's paths.** Confirm them there
  before editing the manifest.

### Acceptance

- After `scoop update mortar`, files Mortar stores for the user are
  still there when those files lived in a persisted relative path.
- If Mortar stores nothing in the app dir, `bucket/mortar.json` still
  has no `persist` key.
- `scripts/update.sh` still only changes version, URLs, and hashes.
- `gate` stays green.
