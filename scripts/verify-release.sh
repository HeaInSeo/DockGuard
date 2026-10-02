#!/usr/bin/env bash
# S2 release verification: a release directory must contain exactly the
# expected assets, SHA256SUMS must cover and match all of them, and the wasm,
# policies.json and both provenance files must agree with the pin.
#
# usage: scripts/verify-release.sh <dir> [vMAJOR.MINOR.PATCH]
#   RELEASE_PIN  pin file (default: release/pin.json)
set -euo pipefail

fail() {
  echo "verify-release: $*" >&2
  exit 1
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 <dir> [vMAJOR.MINOR.PATCH]" >&2
  exit 2
fi
dir="$1"
want_version="${2:-}"
pin="${RELEASE_PIN:-release/pin.json}"
[ -d "$dir" ] || fail "$dir is not a directory"
[ -f "$pin" ] || fail "pin file $pin not found"

assets="dockguard.wasm policies.json provenance.json release-provenance.json"

# 1) Exact asset set: nothing missing, nothing extra.
want_files="$(printf '%s\n' SHA256SUMS $assets | sort)"
got_files="$(ls -A "$dir" | sort)"
[ "$got_files" = "$want_files" ] || fail "asset set mismatch: got [$(echo $got_files)] want [$(echo $want_files)]"

# 2) SHA256SUMS lists exactly the assets once each, and every digest matches.
listed="$(awk '{sub(/^\*/, "", $2); print $2}' "$dir/SHA256SUMS" | sort)"
[ "$listed" = "$(printf '%s\n' $assets | sort)" ] || fail "SHA256SUMS does not list exactly: $assets"
(cd "$dir" && sha256sum --strict --quiet -c SHA256SUMS) || fail "SHA256SUMS verification failed"

sha() { sha256sum "$dir/$1" | cut -d' ' -f1; }
wasm="$(sha dockguard.wasm)"
policies="$(sha policies.json)"
prov="$(sha provenance.json)"

# 3) Artifact digests must equal the pinned rebuild digests.
src_commit="$(jq -er '.policy_source_commit' "$pin")"
pin_opa="$(jq -er '.opa_version' "$pin")"
pin_eps="$(jq -ec '.entrypoints' "$pin")"
[ "$wasm" = "$(jq -er '.wasm_sha256' "$pin")" ] || fail "dockguard.wasm $wasm != pinned digest"
[ "$policies" = "$(jq -er '.policies_json_sha256' "$pin")" ] || fail "policies.json $policies != pinned digest"

# 4) S1 provenance must describe the pinned source, toolchain and entrypoints.
jq -e --arg c "$src_commit" --arg o "$pin_opa" --argjson e "$pin_eps" --arg w "$wasm" --arg p "$policies" \
  '.source_commit == $c and .opa_version == $o and .entrypoints == $e and .wasm_sha256 == $w and .policies_json_sha256 == $p' \
  "$dir/provenance.json" >/dev/null || fail "provenance.json does not match the pin and the assets"

# 5) Release provenance must bind version, both commits and every asset digest.
jq -e --arg c "$src_commit" --arg o "$pin_opa" --argjson e "$pin_eps" --arg w "$wasm" --arg p "$policies" --arg pv "$prov" \
  '(.release_version | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
   and .policy_source_commit == $c
   and (.packaging_commit | test("^[0-9a-f]{40}$"))
   and .opa_version == $o
   and (.opa_binary_sha256 | test("^[0-9a-f]{64}$"))
   and .entrypoints == $e
   and .assets == {"dockguard.wasm": $w, "policies.json": $p, "provenance.json": $pv}' \
  "$dir/release-provenance.json" >/dev/null || fail "release-provenance.json does not match the pin and the assets"
if [ -n "$want_version" ]; then
  got_version="$(jq -r '.release_version' "$dir/release-provenance.json")"
  [ "$got_version" = "$want_version" ] || fail "release_version $got_version != $want_version"
fi

echo "verify-release: OK $(jq -r '.release_version' "$dir/release-provenance.json") source=$src_commit wasm=$wasm"
