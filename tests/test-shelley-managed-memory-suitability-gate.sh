#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

out=$("$ROOT_DIR/run-shelley-managed-memory-suitability-gate.sh" --help 2>&1)
assert_contains "$out" 'test-shelley-managed-smoke-raw-media-runtime-contract.sh'
assert_contains "$out" 'test-shelley-managed-smoke-s2-narrow-fidelity-contract.sh'
assert_contains "$out" 'test-s4-recall-validation-runtime-contract.sh'

out=$("$ROOT_DIR/run-shelley-managed-memory-suitability-gate.sh" --dry-run --required-runtime --s4-softfail-policy strict 2>&1)
assert_contains "$out" '[dry-run]'
assert_contains "$out" 'test-shelley-managed-smoke-raw-media-runtime-contract.sh'
assert_contains "$out" 'test-shelley-managed-smoke-s2-narrow-fidelity-contract.sh'
assert_contains "$out" 'test-s4-recall-validation-runtime-contract.sh'

out=$("$ROOT_DIR/run-shelley-managed-memory-suitability-gate.sh" --s4-softfail-policy nope 2>&1 || true)
assert_contains "$out" '--s4-softfail-policy must be allow or strict'

printf 'shelley managed memory suitability gate tests passed\n'
