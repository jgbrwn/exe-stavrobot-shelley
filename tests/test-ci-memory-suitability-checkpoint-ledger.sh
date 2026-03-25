#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
APPEND="$ROOT_DIR/ci/append-memory-suitability-checkpoint-ledger.sh"
SUMMARY="$ROOT_DIR/ci/render-memory-suitability-ledger-summary.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

out=$("$APPEND" --help 2>&1)
assert_contains "$out" '--ledger-path PATH'
assert_contains "$out" '--outcome pass|fail'

out=$("$SUMMARY" --help 2>&1)
assert_contains "$out" '--ledger-path PATH'
assert_contains "$out" '--last N'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

artifact_dir="$tmpdir/artifacts"
mkdir -p "$artifact_dir"
cat > "$artifact_dir/diagnostics.txt" <<'EOF_DIAG'
timestamp=2026-03-24T18:13:54Z
git_head=d7d67c65c4f56ccb56ec0d00cc5664bc83a98fe1
EOF_DIAG

ledger="$tmpdir/ledger.json"

"$APPEND" \
  --ledger-path "$ledger" \
  --run-ref "local:checkpoint-111" \
  --policy strict \
  --outcome pass \
  --s4-softfail-evidence no \
  --artifact-dir "$artifact_dir" \
  --artifact-ref memory-suitability-required-runtime-artifacts \
  --note-path "$artifact_dir/checkpoint-note.md" >/dev/null

python3 - "$ledger" <<'PY'
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
assert data['schema_version'] == 1
assert len(data['checkpoints']) == 1
entry = data['checkpoints'][0]
assert entry['outcome'] == 'pass'
assert entry['policy'] == 'strict'
assert entry['s4_softfail_evidence'] == 'no'
assert entry['diagnostics_timestamp_utc'] == '2026-03-24T18:13:54Z'
assert entry['git_head'].startswith('d7d67c')
PY

"$APPEND" \
  --ledger-path "$ledger" \
  --run-ref "local:checkpoint-112" \
  --policy strict \
  --outcome fail \
  --s4-softfail-evidence yes \
  --artifact-dir "$artifact_dir" >/dev/null

dup=$("$APPEND" \
  --ledger-path "$ledger" \
  --run-ref "local:checkpoint-112" \
  --policy strict \
  --outcome fail \
  --s4-softfail-evidence yes \
  --artifact-dir "$artifact_dir" 2>&1 || true)
assert_contains "$dup" 'duplicate checkpoint'

"$APPEND" \
  --ledger-path "$ledger" \
  --run-ref "local:checkpoint-112" \
  --policy strict \
  --outcome fail \
  --s4-softfail-evidence yes \
  --artifact-dir "$artifact_dir" \
  --allow-duplicate >/dev/null

summary=$("$SUMMARY" --ledger-path "$ledger" --last 1)
assert_contains "$summary" 'run history (last 1)'
assert_contains "$summary" 'local:checkpoint-112'
assert_contains "$summary" '| fail | strict | yes |'

bad=$("$APPEND" --ledger-path "$ledger" --run-ref x --outcome nope --artifact-dir "$artifact_dir" 2>&1 || true)
assert_contains "$bad" '--outcome must be pass or fail'

echo "ci memory suitability checkpoint ledger tests passed"
