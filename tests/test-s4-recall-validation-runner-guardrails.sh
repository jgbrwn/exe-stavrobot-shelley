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

out=$("$ROOT_DIR/run-shelley-managed-s4-recall-validation.sh" --help 2>&1)
assert_contains "$out" '--require-remote-isolation Fail run if all seeded Shelley conversations do not map to distinct remote Stavrobot conversation IDs'
assert_contains "$out" '--remote-isolation-profile-session'

out=$("$ROOT_DIR/run-shelley-managed-s4-recall-validation.sh" --port 9999 2>&1 || true)
assert_contains "$out" '--port 9999 is reserved for operator/dev Shelley; choose a dedicated validation port'

printf 's4 recall validation runner guardrail tests passed\n'

script=$(cat "$ROOT_DIR/run-shelley-managed-s4-recall-validation.sh")
assert_contains "$script" 'post_json_with_retry()'
assert_contains "$script" 'print_server_log_tail()'
assert_contains "$script" 'Response snippet:'
out=$("$ROOT_DIR/run-shelley-managed-s4-recall-validation.sh" --isolation-bridge-request-timeout nope 2>&1 || true)
assert_contains "$out" '--isolation-bridge-request-timeout must be numeric'

out=$("$ROOT_DIR/run-shelley-managed-s4-recall-validation.sh" --isolation-bridge-retries 0 2>&1 || true)
assert_contains "$out" '--isolation-bridge-retries must be >= 1'
