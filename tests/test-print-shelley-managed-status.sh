#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if grep -Fq "$needle" <<<"$haystack"; then
    printf 'expected output to not contain: %s\n' "$needle" >&2
    printf '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

cat > "$TMP_DIR/profiles.json" <<'JSON'
{
  "bridge_contract_version": 1,
  "profiles": {
    "local-default": {
      "bridge_path": "/bin/sh"
    }
  }
}
JSON

cat > "$TMP_DIR/state-dirty.json" <<'JSON'
{
  "enabled": true,
  "mode": "stavrobot",
  "local_contract": {
    "bridge_contract_version": 1
  },
  "profiles": {
    "available": ["local-default"],
    "default": "local-default"
  },
  "build": {
    "checkout_path": "/does/not/exist",
    "binary_path": "/does/not/exist/bin/shelley",
    "checkout_dirty_at_rebuild": true
  },
  "upstream": {
    "commit": "abc123"
  }
}
JSON

cat > "$TMP_DIR/state-clean.json" <<'JSON'
{
  "enabled": true,
  "mode": "stavrobot",
  "local_contract": {
    "bridge_contract_version": 1
  },
  "profiles": {
    "available": ["local-default"],
    "default": "local-default"
  },
  "build": {
    "checkout_path": "/does/not/exist",
    "binary_path": "/does/not/exist/bin/shelley",
    "checkout_dirty_at_rebuild": false
  },
  "upstream": {
    "commit": "abc123"
  }
}
JSON

cat > "$TMP_DIR/state-older.json" <<'JSON'
{
  "enabled": true,
  "mode": "stavrobot",
  "local_contract": {
    "bridge_contract_version": 1
  },
  "profiles": {
    "available": ["local-default"],
    "default": "local-default"
  },
  "build": {
    "checkout_path": "/does/not/exist",
    "binary_path": "/does/not/exist/bin/shelley"
  },
  "upstream": {
    "commit": "abc123"
  }
}
JSON

dirty_output=$("$ROOT_DIR/print-shelley-managed-status.sh" --state-file "$TMP_DIR/state-dirty.json" --profile-state-file "$TMP_DIR/profiles.json")
assert_contains "$dirty_output" 'recorded_checkout_dirty_at_rebuild: yes'
assert_contains "$dirty_output" 'warnings:'
assert_contains "$dirty_output" '  - last recorded managed rebuild used a dirty checkout'

clean_output=$("$ROOT_DIR/print-shelley-managed-status.sh" --state-file "$TMP_DIR/state-clean.json" --profile-state-file "$TMP_DIR/profiles.json")
assert_contains "$clean_output" 'recorded_checkout_dirty_at_rebuild: no'
assert_not_contains "$clean_output" 'warnings:'
assert_not_contains "$clean_output" 'last recorded managed rebuild used a dirty checkout'

older_output=$("$ROOT_DIR/print-shelley-managed-status.sh" --state-file "$TMP_DIR/state-older.json" --profile-state-file "$TMP_DIR/profiles.json")
assert_contains "$older_output" 'recorded_checkout_dirty_at_rebuild: unknown'
assert_contains "$older_output" 'notes:'
assert_contains "$older_output" '  - recorded rebuild provenance does not include checkout_dirty_at_rebuild (older state file)'
assert_not_contains "$older_output" 'warnings:'

printf 'print-shelley-managed-status tests passed\n'
