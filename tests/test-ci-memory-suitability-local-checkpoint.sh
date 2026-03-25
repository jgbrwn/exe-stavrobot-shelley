#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
RUNNER="$ROOT_DIR/ci/run-memory-suitability-local-checkpoint.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

out=$("$RUNNER" --help 2>&1)
assert_contains "$out" '--policy MODE'
assert_contains "$out" '--artifact-root-dir PATH'

out=$("$RUNNER" --dry-run --run-ref local:test 2>&1)
assert_contains "$out" '[dry-run] run_ref=local:test'
assert_contains "$out" 'check-memory-suitability-runtime-prereqs.sh'
assert_contains "$out" 'record-memory-suitability-checkpoint.sh'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_pre="$tmpdir/pre.sh"
stub_gate="$tmpdir/gate.sh"
stub_collect="$tmpdir/collect.sh"
stub_record="$tmpdir/record.sh"
log_file="$tmpdir/log.txt"

cat > "$stub_pre" <<'EOF_PRE'
#!/usr/bin/env bash
echo "pre:$*" >> "$TEST_LOG"
exit 0
EOF_PRE

cat > "$stub_gate" <<'EOF_GATE'
#!/usr/bin/env bash
echo "gate:$*" >> "$TEST_LOG"
exit 0
EOF_GATE

cat > "$stub_collect" <<'EOF_COLLECT'
#!/usr/bin/env bash
set -euo pipefail
echo "collect:$*" >> "$TEST_LOG"
out_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) out_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$out_dir"
cat > "$out_dir/diagnostics.txt" <<'EOF_D'
timestamp=2026-03-25T00:00:00Z
git_head=abc123abc123abc123
EOF_D
cat > "$out_dir/manifest.txt" <<'EOF_M'
diagnostics.txt <= generated
EOF_M
cat > "$out_dir/s4-last-report.json" <<'EOF_R'
{"raw":{"bridge_softfail":"context_overflow"}}
EOF_R
exit 0
EOF_COLLECT

cat > "$stub_record" <<'EOF_RECORD'
#!/usr/bin/env bash
echo "record:$*" >> "$TEST_LOG"
exit 0
EOF_RECORD

chmod +x "$stub_pre" "$stub_gate" "$stub_collect" "$stub_record"

TEST_LOG="$log_file" \
MEMORY_SUITABILITY_PRECHECK_CMD="$stub_pre" \
MEMORY_SUITABILITY_GATE_CMD="$stub_gate" \
MEMORY_SUITABILITY_COLLECT_CMD="$stub_collect" \
MEMORY_SUITABILITY_RECORD_CMD="$stub_record" \
"$RUNNER" --artifact-root-dir "$tmpdir/state" --run-ref local:stub-run >/dev/null

log_out=$(cat "$log_file")
assert_contains "$log_out" 'pre:'
assert_contains "$log_out" 'gate:'
assert_contains "$log_out" 'collect:'
assert_contains "$log_out" 'record:'
assert_contains "$log_out" '--outcome pass'
assert_contains "$log_out" '--s4-softfail-evidence yes'
assert_contains "$log_out" '--run-ref local:stub-run'

bad=$("$RUNNER" --dry-run --policy nope 2>&1 || true)
assert_contains "$bad" '--policy must be allow or strict'

echo "ci memory suitability local checkpoint runner tests passed"
