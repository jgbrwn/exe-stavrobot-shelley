#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_DIR=""
RUN_URL=""
OUTPUT_PATH=""

usage() {
  cat <<'USAGE'
Usage: ./ci/render-memory-suitability-checkpoint-note.sh --artifact-dir PATH --run-url URL [--output PATH]

Renders a markdown checkpoint note from CI artifact bundle contents.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-dir)
      ARTIFACT_DIR="$2"
      shift 2
      ;;
    --run-url)
      RUN_URL="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "[error] Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -n "$ARTIFACT_DIR" ]] || { echo "[error] --artifact-dir is required" >&2; exit 1; }
[[ -n "$RUN_URL" ]] || { echo "[error] --run-url is required" >&2; exit 1; }
[[ -d "$ARTIFACT_DIR" ]] || { echo "[error] Artifact dir not found: $ARTIFACT_DIR" >&2; exit 1; }

manifest="$ARTIFACT_DIR/manifest.txt"
diagnostics="$ARTIFACT_DIR/diagnostics.txt"
report="$ARTIFACT_DIR/s4-last-report.json"

status="unknown"
if [[ -f "$report" ]]; then
  status="present"
fi

diag_stamp=""
if [[ -f "$diagnostics" ]]; then
  diag_stamp=$(awk -F= '/^timestamp=/{print $2; exit}' "$diagnostics" || true)
fi

render() {
  cat <<EOF
### CI strict memory-suitability checkpoint

- run: $RUN_URL
- artifact_dir: $ARTIFACT_DIR
- diagnostics_timestamp_utc: ${diag_stamp:-unknown}
- s4_last_report: $status

Artifact files:
$(if [[ -f "$manifest" ]]; then sed 's/^/- /' "$manifest"; else echo '- manifest.txt missing'; fi)

Notes:
- CI lane policy: S4 softfail policy is strict.
- If this checkpoint failed, inspect s4-server.log and diagnostics.txt first.
EOF
}

if [[ -n "$OUTPUT_PATH" ]]; then
  render > "$OUTPUT_PATH"
  echo "[info] wrote checkpoint note to $OUTPUT_PATH"
else
  render
fi
