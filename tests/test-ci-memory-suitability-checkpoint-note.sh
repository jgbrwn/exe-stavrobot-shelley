#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
RENDERER="$ROOT_DIR/ci/render-memory-suitability-checkpoint-note.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

out=$("$RENDERER" --help 2>&1)
assert_contains "$out" '--artifact-dir PATH'
assert_contains "$out" '--run-url URL'

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
cat > "$tmpdir/manifest.txt" <<'EOF_MAN'
s4-server.log <= /tmp/shelley-s4-recall-validation.log
s4-last-report.json <= /repo/state/s4-recall-validation-last.json
EOF_MAN
cat > "$tmpdir/diagnostics.txt" <<'EOF_DIAG'
timestamp=2026-03-24T00:00:00Z
repo_dir=/home/exedev/exe-stavrobot-shelley
EOF_DIAG
cat > "$tmpdir/s4-last-report.json" <<'EOF_REP'
{"schema_version":1}
EOF_REP

out=$("$RENDERER" --artifact-dir "$tmpdir" --run-url "https://github.com/org/repo/actions/runs/123")
assert_contains "$out" 'CI strict memory-suitability checkpoint'
assert_contains "$out" 'https://github.com/org/repo/actions/runs/123'
assert_contains "$out" 'diagnostics_timestamp_utc: 2026-03-24T00:00:00Z'
assert_contains "$out" '- s4-server.log <= /tmp/shelley-s4-recall-validation.log'

outfile="$tmpdir/note.md"
"$RENDERER" --artifact-dir "$tmpdir" --run-url "https://x" --output "$outfile" >/dev/null
[[ -f "$outfile" ]] || { echo 'note output missing' >&2; exit 1; }

echo "ci memory suitability checkpoint note tests passed"
