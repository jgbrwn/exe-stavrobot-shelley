#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
CI_RUNNER="$ROOT_DIR/ci/run-memory-suitability-required-runtime.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

out=$("$CI_RUNNER" --help 2>&1)
assert_contains "$out" 'Authoritative CI entrypoint'
assert_contains "$out" '--required-runtime'
assert_contains "$out" '--profile-state-path'

out=$("$CI_RUNNER" --dry-run 2>&1)
assert_contains "$out" '[dry-run]'
assert_contains "$out" 'run-shelley-managed-memory-suitability-gate.sh'
assert_contains "$out" '--required-runtime'

out=$("$CI_RUNNER" --dry-run --full-suite 2>&1)
assert_contains "$out" '--full-suite'

echo "ci required-runtime memory suitability lane tests passed"
