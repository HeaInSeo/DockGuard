#!/usr/bin/env bash
# S2 negative fixtures: package one good release, then prove that packaging
# and verification reject wrong inputs and tampered or incomplete releases.
#
# usage: scripts/test-release-negative.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
pin="release/pin.json"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
expect_fail() {
  local name="$1"
  shift
  if "$@" >"$tmp/out.log" 2>&1; then
    echo "NEGATIVE NOT REJECTED: $name" >&2
    cat "$tmp/out.log" >&2
    failures=$((failures + 1))
  else
    echo "rejected as expected: $name ($(tail -n1 "$tmp/out.log"))"
  fi
}

# Copy of the good release for one mutation.
fresh() {
  rm -rf "$tmp/case"
  cp -a "$tmp/good" "$tmp/case"
}
resum() { (cd "$tmp/case" && sha256sum dockguard.wasm policies.json provenance.json release-provenance.json >SHA256SUMS); }
jq_edit() {
  jq "$2" "$tmp/case/$1" >"$tmp/edit.json"
  mv "$tmp/edit.json" "$tmp/case/$1"
}
# Re-bind release-provenance.json to the current provenance.json digest, so a
# provenance.json edit can only be caught by the provenance.json check itself.
relink_prov() { jq_edit release-provenance.json ".assets[\"provenance.json\"] = \"$(sha256sum "$tmp/case/provenance.json" | cut -d' ' -f1)\""; }
flip_byte() {
  local f="$1" size offset orig
  size="$(stat -c %s "$f")"
  offset=$((size / 2))
  orig="$(od -An -tu1 -j "$offset" -N1 "$f" | tr -d ' ')"
  printf "$(printf '\\%03o' $(((orig + 1) % 256)))" |
    dd of="$f" bs=1 seek="$offset" count=1 conv=notrunc status=none
}
pin_with() {
  jq "$1" "$pin" >"$tmp/pin.json"
}
verify() { bash scripts/verify-release.sh "$@"; }
package() { bash scripts/package-release.sh "$@"; }

# Positive control.
package v0.0.0 "$tmp/good" >/dev/null
verify "$tmp/good" v0.0.0 >/dev/null
echo "positive control: good release verifies"

# --- verification negatives -------------------------------------------------
fresh
rm "$tmp/case/policies.json"
expect_fail "missing asset" verify "$tmp/case"

fresh
echo stray >"$tmp/case/extra.txt"
expect_fail "extra asset" verify "$tmp/case"

fresh
rm "$tmp/case/SHA256SUMS"
expect_fail "missing SHA256SUMS" verify "$tmp/case"

fresh
grep -v ' release-provenance.json$' "$tmp/good/SHA256SUMS" >"$tmp/case/SHA256SUMS"
expect_fail "SHA256SUMS does not cover an asset" verify "$tmp/case"

fresh
flip_byte "$tmp/case/dockguard.wasm"
expect_fail "wasm byte flip (sha mismatch)" verify "$tmp/case"

# Only SHA256SUMS covers release-provenance.json, so a stale SUMS entry for a
# field no other check reads must be rejected by the SUMS digest check.
fresh
jq_edit release-provenance.json '.packaging_commit = "0000000000000000000000000000000000000000"'
expect_fail "release-provenance.json edited without re-sum (stale SHA256SUMS)" verify "$tmp/case"

fresh
flip_byte "$tmp/case/dockguard.wasm"
tampered="$(sha256sum "$tmp/case/dockguard.wasm" | cut -d' ' -f1)"
jq_edit provenance.json ".wasm_sha256 = \"$tampered\""
jq_edit release-provenance.json ".assets[\"dockguard.wasm\"] = \"$tampered\" | .assets[\"provenance.json\"] = \"$(sha256sum "$tmp/case/provenance.json" | cut -d' ' -f1)\""
resum
expect_fail "wasm tampered with consistent SHA256SUMS (digest != pin)" verify "$tmp/case"

fresh
jq_edit provenance.json ".source_commit = \"$(git rev-parse HEAD)\""
relink_prov
resum
expect_fail "provenance from another source commit" verify "$tmp/case"

fresh
jq_edit release-provenance.json '.policy_source_commit = "0000000000000000000000000000000000000000"'
resum
expect_fail "release provenance names another source" verify "$tmp/case"

fresh
jq_edit release-provenance.json '.entrypoints = ["dockerfile/security/deny", "dockerfile/multistage/deny"]'
resum
expect_fail "entrypoint order changed" verify "$tmp/case"

fresh
jq_edit provenance.json '.opa_version = "1.4.1"'
relink_prov
resum
expect_fail "provenance toolchain mismatch" verify "$tmp/case"

fresh
jq_edit release-provenance.json '.assets["policies.json"] = "0000000000000000000000000000000000000000000000000000000000000000"'
resum
expect_fail "release provenance asset digest mismatch" verify "$tmp/case"

fresh
expect_fail "release version mismatch" verify "$tmp/case" v9.9.9

# --- packaging negatives ----------------------------------------------------
expect_fail "version without v prefix" package 1.0.0 "$tmp/p1"
expect_fail "partial version" package v1.0 "$tmp/p2"
expect_fail "non-empty output dir" package v0.0.0 "$tmp/good"

pin_with '.policy_source_commit = "04ceceb"'
expect_fail "short policy source SHA" env RELEASE_PIN="$tmp/pin.json" bash scripts/package-release.sh v0.0.0 "$tmp/p3"

pin_with '.policy_source_commit = "main"'
expect_fail "branch name as policy source" env RELEASE_PIN="$tmp/pin.json" bash scripts/package-release.sh v0.0.0 "$tmp/p4"

pin_with '.policy_source_commit = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"'
expect_fail "unknown policy source commit" env RELEASE_PIN="$tmp/pin.json" bash scripts/package-release.sh v0.0.0 "$tmp/p5"

# An existing commit that is not an ancestor of HEAD (no ref is created).
orphan="$(GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid \
  git commit-tree -m "negative fixture: unrelated source" "$(jq -r .policy_source_commit "$pin")^{tree}")"
pin_with ".policy_source_commit = \"$orphan\""
expect_fail "policy source not reachable from HEAD" env RELEASE_PIN="$tmp/pin.json" bash scripts/package-release.sh v0.0.0 "$tmp/p6"

pin_with '.wasm_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"'
expect_fail "rebuild wasm digest != pin" env RELEASE_PIN="$tmp/pin.json" bash scripts/package-release.sh v0.0.0 "$tmp/p7"

pin_with '.entrypoints = ["dockerfile/security/deny"]'
expect_fail "rebuild entrypoints != pin" env RELEASE_PIN="$tmp/pin.json" bash scripts/package-release.sh v0.0.0 "$tmp/p8"

pin_with '.opa_version = "1.4.1"'
expect_fail "toolchain version != pin" env RELEASE_PIN="$tmp/pin.json" bash scripts/package-release.sh v0.0.0 "$tmp/p9"

if [ "$failures" -ne 0 ]; then
  echo "$failures negative case(s) were not rejected" >&2
  exit 1
fi
echo "all release negatives rejected"
