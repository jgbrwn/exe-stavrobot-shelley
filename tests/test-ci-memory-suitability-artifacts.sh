#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
COLLECTOR="$ROOT_DIR/ci/collect-memory-suitability-artifacts.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

out=$("$COLLECTOR" --help 2>&1)
assert_contains "$out" '--output-dir PATH'
assert_contains "$out" 'S4_SERVER_LOG_PATH'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fake_log="$tmpdir/fake.log"
fake_contract="$tmpdir/fake-contract.json"
fake_report="$tmpdir/fake-report.json"
printf 'logline\n' > "$fake_log"
printf '{"ok":true}\n' > "$fake_contract"
printf '{"schema_version":1}\n' > "$fake_report"

outdir="$tmpdir/out"
S4_SERVER_LOG_PATH="$fake_log" \
S4_RUNTIME_CONTRACT_JSON_PATH="$fake_contract" \
S4_LAST_REPORT_PATH="$fake_report" \
"$COLLECTOR" --output-dir "$outdir" --repo-dir "$ROOT_DIR" >/dev/null

[[ -f "$outdir/s4-server.log" ]] || { echo 'missing s4-server.log' >&2; exit 1; }
[[ -f "$outdir/s4-runtime-contract.json" ]] || { echo 'missing s4-runtime-contract.json' >&2; exit 1; }
[[ -f "$outdir/s4-last-report.json" ]] || { echo 'missing s4-last-report.json' >&2; exit 1; }
[[ -f "$outdir/diagnostics.txt" ]] || { echo 'missing diagnostics.txt' >&2; exit 1; }
[[ -f "$outdir/manifest.txt" ]] || { echo 'missing manifest.txt' >&2; exit 1; }

manifest=$(cat "$outdir/manifest.txt")
assert_contains "$manifest" 's4-server.log'
assert_contains "$manifest" 's4-runtime-contract.json'
assert_contains "$manifest" 's4-last-report.json'

echo "ci memory suitability artifact collector tests passed"
