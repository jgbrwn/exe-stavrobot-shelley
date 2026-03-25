#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
INSTALLER="$ROOT_DIR/ci/install-memory-suitability-local-checkpoint-timer.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

out=$("$INSTALLER" --help 2>&1)
assert_contains "$out" '--on-calendar SPEC'
assert_contains "$out" '--dry-run'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

sysdir="$tmpdir/systemd"
out=$("$INSTALLER" \
  --repo-dir "$ROOT_DIR" \
  --systemd-dir "$sysdir" \
  --run-user testuser \
  --run-group testgroup \
  --on-calendar 'daily' \
  --no-enable \
  --dry-run 2>&1)

assert_contains "$out" '[dry-run] write'
assert_contains "$out" 'memory-suitability-local-checkpoint.service'
assert_contains "$out" 'memory-suitability-local-checkpoint.timer'

"$INSTALLER" \
  --repo-dir "$ROOT_DIR" \
  --systemd-dir "$sysdir" \
  --run-user testuser \
  --run-group testgroup \
  --on-calendar 'daily' \
  --no-enable >/dev/null

service="$sysdir/memory-suitability-local-checkpoint.service"
timer="$sysdir/memory-suitability-local-checkpoint.timer"

[[ -f "$service" ]] || { echo 'missing service unit' >&2; exit 1; }
[[ -f "$timer" ]] || { echo 'missing timer unit' >&2; exit 1; }

service_out=$(cat "$service")
assert_contains "$service_out" 'User=testuser'
assert_contains "$service_out" 'Group=testgroup'
assert_contains "$service_out" 'run-memory-suitability-local-checkpoint.sh --policy strict'

timer_out=$(cat "$timer")
assert_contains "$timer_out" 'OnCalendar=daily'
assert_contains "$timer_out" 'Persistent=true'

echo "ci memory suitability local checkpoint timer install tests passed"
