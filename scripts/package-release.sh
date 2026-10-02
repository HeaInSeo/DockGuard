#!/usr/bin/env bash
# S2 release packaging: rebuild the S1 bundle from the pinned policy source
# commit (release/pin.json) and package it as a versioned release.
#
# The packaging commit (HEAD, which carries this script and the pin) and the
# policy source commit (the commit the wasm is built from) are recorded
# separately. A git commit SHA is not an artifact digest; digests are sha256.
#
# usage: scripts/package-release.sh <vMAJOR.MINOR.PATCH> <outdir>
#   RELEASE_PIN  pin file (default: release/pin.json)
set -euo pipefail

fail() {
  echo "package-release: $*" >&2
  exit 1
}

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <vMAJOR.MINOR.PATCH> <outdir>" >&2
  exit 2
fi
version="$1"
out="$(realpath -m "$2")"
pin="$(realpath -m "${RELEASE_PIN:-release/pin.json}")"
here="$(cd "$(dirname "$0")" && pwd)"
cd "$(git rev-parse --show-toplevel)"

[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid version '$version' (want vMAJOR.MINOR.PATCH)"
[ -f "$pin" ] || fail "pin file $pin not found"

src_commit="$(jq -er '.policy_source_commit' "$pin")"
pin_opa="$(jq -er '.opa_version' "$pin")"
pin_eps="$(jq -ec '.entrypoints | if type == "array" and length > 0 then . else error("entrypoints must be a non-empty array") end' "$pin")"
pin_wasm="$(jq -er '.wasm_sha256' "$pin")"
pin_policies="$(jq -er '.policies_json_sha256' "$pin")"

# 1) The policy source must be a full commit SHA reachable from the packaging
#    commit. A branch name, tag, short SHA or unrelated commit is rejected.
[[ "$src_commit" =~ ^[0-9a-f]{40}$ ]] || fail "policy_source_commit must be a full 40-hex commit SHA: '$src_commit'"
packaging_commit="$(git rev-parse HEAD)"
git cat-file -e "${src_commit}^{commit}" 2>/dev/null || fail "policy source commit $src_commit not found (shallow checkout?)"
git merge-base --is-ancestor "$src_commit" "$packaging_commit" ||
  fail "policy source $src_commit is not an ancestor of packaging commit $packaging_commit"

# 2) The toolchain must match the pin.
opa_version="$(opa version | sed -n 's/^Version: //p')"
[ "$opa_version" = "$pin_opa" ] || fail "opa version '$opa_version' != pinned '$pin_opa'"
opa_sha256="$(sha256sum "$(command -v opa)" | cut -d' ' -f1)"

mkdir -p "$out"
[ -z "$(ls -A "$out")" ] || fail "output dir $out is not empty"

# 3) Build the S1 bundle in a detached worktree of the policy source.
work="$(mktemp -d)"
cleanup() {
  git worktree remove --force "$work/src" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
git worktree add --quiet --detach "$work/src" "$src_commit"
make -C "$work/src" bundle >/dev/null
b="$work/src/build"

# 4) The rebuild must reproduce the pinned digests and entrypoint order.
wasm_sha="$(sha256sum "$b/dockguard.wasm" | cut -d' ' -f1)"
policies_sha="$(sha256sum "$b/policies.json" | cut -d' ' -f1)"
[ "$wasm_sha" = "$pin_wasm" ] || fail "rebuilt dockguard.wasm $wasm_sha != pinned $pin_wasm"
[ "$policies_sha" = "$pin_policies" ] || fail "rebuilt policies.json $policies_sha != pinned $pin_policies"
got_eps="$(jq -c '[.wasm[].entrypoint]' "$b/wasm/.manifest")"
[ "$got_eps" = "$pin_eps" ] || fail "bundle manifest entrypoints $got_eps != pinned $pin_eps"
jq -e --arg c "$src_commit" --arg o "$pin_opa" --argjson e "$pin_eps" --arg w "$pin_wasm" --arg p "$pin_policies" \
  '.source_commit == $c and .opa_version == $o and .entrypoints == $e and .wasm_sha256 == $w and .policies_json_sha256 == $p' \
  "$b/provenance.json" >/dev/null || fail "S1 provenance.json does not match the pin"

# 5) Assemble the release assets.
cp "$b/dockguard.wasm" "$b/policies.json" "$b/provenance.json" "$out/"
jq -n \
  --arg version "$version" \
  --arg src "$src_commit" \
  --arg pkg "$packaging_commit" \
  --arg opa "$opa_version" \
  --arg opa_sha "$opa_sha256" \
  --argjson eps "$pin_eps" \
  --arg wasm "$wasm_sha" \
  --arg policies "$policies_sha" \
  --arg prov "$(sha256sum "$out/provenance.json" | cut -d' ' -f1)" \
  '{release_version: $version, policy_source_commit: $src, packaging_commit: $pkg,
    opa_version: $opa, opa_binary_sha256: $opa_sha, entrypoints: $eps,
    assets: {"dockguard.wasm": $wasm, "policies.json": $policies, "provenance.json": $prov}}' \
  >"$out/release-provenance.json"
(cd "$out" && sha256sum dockguard.wasm policies.json provenance.json release-provenance.json >SHA256SUMS)

# 6) Self-check with the same verifier a publisher or consumer runs.
RELEASE_PIN="$pin" bash "$here/verify-release.sh" "$out" "$version"
