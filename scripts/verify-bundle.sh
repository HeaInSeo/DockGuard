#!/usr/bin/env bash
# S1 bundle verification: reproducible build, manifest entrypoint order, and a
# byte-flip negative proof for SHA256SUMS.
#
# usage: scripts/verify-bundle.sh <entrypoint>...
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <entrypoint>..." >&2
  exit 2
fi
expected="$(printf '%s\n' "$@" | jq -Rsc 'split("\n")[:-1]')"

# 1) Two clean builds from the same commit must be byte-identical.
make bundle >/dev/null
first="$(mktemp -d)"
cp build/dockguard.wasm build/policies.json "$first/"
rm -rf build
make bundle >/dev/null
for f in dockguard.wasm policies.json; do
  a="$(sha256sum "$first/$f" | cut -d' ' -f1)"
  b="$(sha256sum "build/$f" | cut -d' ' -f1)"
  if [ "$a" != "$b" ]; then
    echo "not reproducible: $f $a != $b" >&2
    exit 1
  fi
  echo "reproducible: $f $a"
done

# 2) Bundle manifest must list the wasm entrypoints in the pinned order.
got="$(jq -c '[.wasm[].entrypoint]' build/wasm/.manifest)"
if [ "$got" != "$expected" ]; then
  echo "manifest entrypoints $got != $expected" >&2
  exit 1
fi
echo "manifest entrypoints: $got"
prov="$(jq -c '.entrypoints' build/provenance.json)"
if [ "$prov" != "$expected" ]; then
  echo "provenance entrypoints $prov != $expected" >&2
  exit 1
fi

# 3) SHA256SUMS must verify, and must reject a single flipped byte.
(cd build && sha256sum -c SHA256SUMS)
tampered="$(mktemp -d)"
cp build/dockguard.wasm build/policies.json build/provenance.json build/SHA256SUMS "$tampered/"
size="$(stat -c %s "$tampered/dockguard.wasm")"
offset=$((size / 2))
orig="$(od -An -tu1 -j "$offset" -N1 "$tampered/dockguard.wasm" | tr -d ' ')"
printf "$(printf '\\%03o' $(((orig + 1) % 256)))" |
  dd of="$tampered/dockguard.wasm" bs=1 seek="$offset" count=1 conv=notrunc status=none
if (cd "$tampered" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
  echo "byte-flip negative FAILED: tampered wasm still matches SHA256SUMS" >&2
  exit 1
fi
echo "byte-flip negative OK: tampered wasm at offset $offset rejected"
