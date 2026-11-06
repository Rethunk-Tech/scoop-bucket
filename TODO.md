# TODO

Work that is decided but not built. `README.md` describes what exists; this
file is the only place that describes what does not.

Sections are unordered.

## checkver has no autoupdate, so Scoop itself cannot bump hashes

`bucket/mortar.json` has `checkver.github` at `:24` and no `autoupdate` object.
`scoop status` can see a newer GitHub tag. `scoop update mortar` still
installs whatever this bucket last committed: URLs and SHA-256 pins only
move when `scripts/update.sh` rewrites the manifest after a GPG check of
`SHA256SUMS`. That split is deliberate. `dea4f99` dropped unsigned
`autoupdate` so Scoop would not fetch the exe and hash it itself.

A maintainer who runs `scoop update` inside this bucket, or a user whose
clone of the bucket is stale, sees a new version from `checkver` and no
safe way for Scoop to fill hashes. The scheduled workflow in
`.github/workflows/update.yml:22` is the only writer.

Decided shape: keep `checkver` as the version probe. Do not add Scoop
`autoupdate` that hashes `mortar-windows-*.exe` over HTTPS. If Scoop later
gains a way to take hashes from a signed `SHA256SUMS` (hashurl plus a
signature check, or a `pre_update` that calls this repo's script), wire
that here and drop the scheduled commit only after `scoop update` refuses
an unsigned SUMS the same way `update.sh:51` refuses a missing `VALIDSIG`.

Rejected: restoring `autoupdate` with `hash` downloaded from the exe. That
is the unsigned path `dea4f99` removed. Rejected: deleting `checkver`.
`scoop status` would go blind.

This leaves `scripts/update.sh` as the only hash writer and does not change
the install contract of `bucket/mortar.json`.

### Read

1. `bucket/mortar.json:24` `checkver` — GitHub tag probe, no sibling
   `autoupdate`.
2. `scripts/update.sh:51` `VALIDSIG $FPR` — the check Scoop autoupdate
   cannot perform today.
3. `.github/workflows/update.yml:22` — the six-hour writer that calls
   `scripts/update.sh`.
4. `README.md:19` — documents signed `SHA256SUMS` as the hash source.

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
