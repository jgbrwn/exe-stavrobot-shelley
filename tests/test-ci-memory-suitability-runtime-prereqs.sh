#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
CHECKER="$ROOT_DIR/ci/check-memory-suitability-runtime-prereqs.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

out=$("$CHECKER" --help 2>&1)
assert_contains "$out" 'Preflight checker for the required-runtime memory-suitability CI lane'
assert_contains "$out" '--json'
assert_contains "$out" '--profile-state-path'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
missing_profile="$tmpdir/not-there.json"
out=$("$CHECKER" --shelley-dir "$tmpdir" --profile-state-path "$missing_profile" --json 2>&1 || true)
assert_contains "$out" '"ok": false'
assert_contains "$out" 'managed_shelley_binary:'
assert_contains "$out" 'profile_state:'
assert_contains "$out" '"stavrobot_config": "/tmp/stavrobot/data/main/config.toml"'

echo "ci required-runtime memory suitability preflight tests passed"
