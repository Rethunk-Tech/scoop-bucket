#!/usr/bin/env bash
# verify_sums SUMS ASC KEYRING FPR GNUPGHOME-DIR: succeeds only for a VALIDSIG from exactly FPR.
# gpg exits 0 and prints VALIDSIG for a signature by an expired or revoked key, so those are rejected here.
verify_sums() {
  local sums=$1 asc=$2 keyring=$3 fpr=$4 home=$5 status
  install -d -m 700 "$home"
  status=$home/status
  GNUPGHOME=$home gpg --batch --quiet --import "$keyring" 2>/dev/null || return 1
  GNUPGHOME=$home gpg --batch --status-fd 1 --verify "$asc" "$sums" >"$status" 2>/dev/null || true
  grep -q "^\[GNUPG:\] VALIDSIG $fpr " "$status" && ! grep -qE '^\[GNUPG:\] (REVKEYSIG|EXPKEYSIG) ' "$status"
}
