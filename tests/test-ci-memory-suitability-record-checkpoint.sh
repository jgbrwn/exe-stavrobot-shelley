#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
RECORDER="$ROOT_DIR/ci/record-memory-suitability-checkpoint.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

out=$("$RECORDER" --help 2>&1)
assert_contains "$out" '--artifact-dir PATH'
assert_contains "$out" '--outcome pass|fail'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

artifact_dir="$tmpdir/ci-artifacts"
mkdir -p "$artifact_dir"
cat > "$artifact_dir/manifest.txt" <<'EOF_MAN'
s4-last-report.json <= /repo/state/s4-recall-validation-last.json
EOF_MAN
cat > "$artifact_dir/diagnostics.txt" <<'EOF_DIAG'
timestamp=2026-03-24T18:13:54Z
git_head=d7d67c65c4f56ccb56ec0d00cc5664bc83a98fe1
EOF_DIAG
cat > "$artifact_dir/s4-last-report.json" <<'EOF_REP'
{"schema_version":1}
EOF_REP

ledger="$tmpdir/ledger.json"
summary="$tmpdir/summary.md"
note="$tmpdir/note.md"

"$RECORDER" \
  --artifact-dir "$artifact_dir" \
  --run-ref "local:checkpoint-999" \
  --outcome pass \
  --policy strict \
  --s4-softfail-evidence no \
  --artifact-ref memory-suitability-required-runtime-artifacts \
  --note-path "$note" \
  --ledger-path "$ledger" \
  --summary-path "$summary" \
  --last 5 >/dev/null

[[ -f "$note" ]] || { echo 'expected note file' >&2; exit 1; }
[[ -f "$ledger" ]] || { echo 'expected ledger file' >&2; exit 1; }
[[ -f "$summary" ]] || { echo 'expected summary file' >&2; exit 1; }

note_out=$(cat "$note")
assert_contains "$note_out" 'Local strict memory-suitability checkpoint'
assert_contains "$note_out" 'local:checkpoint-999'

summary_out=$(cat "$summary")
assert_contains "$summary_out" 'run history (last 5)'
assert_contains "$summary_out" '| pass | strict | no |'

python3 - "$ledger" <<'PY'
import json
import sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
assert len(data['checkpoints']) == 1
entry = data['checkpoints'][0]
assert entry['outcome'] == 'pass'
assert entry['run_ref'] == 'local:checkpoint-999'
assert entry['note_path'].endswith('/note.md')
PY

bad=$("$RECORDER" --artifact-dir "$artifact_dir" --run-ref x --outcome pass --last nope 2>&1 || true)
assert_contains "$bad" '--last must be a non-negative integer'

echo "ci memory suitability record-checkpoint tests passed"
