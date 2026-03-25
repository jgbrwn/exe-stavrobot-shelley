#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
RENDER_NOTE="$ROOT_DIR/ci/render-memory-suitability-checkpoint-note.sh"
APPEND_LEDGER="$ROOT_DIR/ci/append-memory-suitability-checkpoint-ledger.sh"
RENDER_SUMMARY="$ROOT_DIR/ci/render-memory-suitability-ledger-summary.sh"

ARTIFACT_DIR=""
RUN_URL=""
OUTCOME=""
POLICY="strict"
SOFTFAIL_EVIDENCE="unknown"
LEDGER_PATH="$ROOT_DIR/docs/checkpoints/memory-suitability-required-runtime-ledger.json"
SUMMARY_PATH="$ROOT_DIR/docs/checkpoints/memory-suitability-required-runtime-summary.md"
NOTE_PATH=""
ARTIFACT_REF="memory-suitability-required-runtime-artifacts"
LAST_N=10

usage() {
  cat <<'USAGE'
Usage: ./ci/record-memory-suitability-checkpoint.sh --artifact-dir PATH --run-url URL --outcome pass|fail [flags]

Render checkpoint note, append ledger entry, and regenerate summary in one command.

Required:
  --artifact-dir PATH             Directory containing collected CI artifacts
  --run-url URL                   GitHub Actions run URL
  --outcome STATUS                STATUS=pass|fail

Optional:
  --policy MODE                   MODE=allow|strict (default: strict)
  --s4-softfail-evidence STATE    STATE=yes|no|unknown (default: unknown)
  --artifact-ref TEXT             Artifact handle/name (default: memory-suitability-required-runtime-artifacts)
  --note-path PATH                Checkpoint note output path (default: <artifact-dir>/checkpoint-note.md)
  --ledger-path PATH              Ledger JSON path
  --summary-path PATH             Summary markdown path
  --last N                        Summary history depth (default: 10)
  --help
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
    --outcome)
      OUTCOME="$2"
      shift 2
      ;;
    --policy)
      POLICY="$2"
      shift 2
      ;;
    --s4-softfail-evidence)
      SOFTFAIL_EVIDENCE="$2"
      shift 2
      ;;
    --artifact-ref)
      ARTIFACT_REF="$2"
      shift 2
      ;;
    --note-path)
      NOTE_PATH="$2"
      shift 2
      ;;
    --ledger-path)
      LEDGER_PATH="$2"
      shift 2
      ;;
    --summary-path)
      SUMMARY_PATH="$2"
      shift 2
      ;;
    --last)
      LAST_N="$2"
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
[[ -d "$ARTIFACT_DIR" ]] || { echo "[error] Artifact dir not found: $ARTIFACT_DIR" >&2; exit 1; }
[[ -n "$RUN_URL" ]] || { echo "[error] --run-url is required" >&2; exit 1; }
[[ -n "$OUTCOME" ]] || { echo "[error] --outcome is required" >&2; exit 1; }
[[ "$LAST_N" =~ ^[0-9]+$ ]] || { echo "[error] --last must be a non-negative integer" >&2; exit 1; }

if [[ -z "$NOTE_PATH" ]]; then
  NOTE_PATH="$ARTIFACT_DIR/checkpoint-note.md"
fi

mkdir -p "$(dirname "$LEDGER_PATH")"
mkdir -p "$(dirname "$SUMMARY_PATH")"
mkdir -p "$(dirname "$NOTE_PATH")"

"$RENDER_NOTE" --artifact-dir "$ARTIFACT_DIR" --run-url "$RUN_URL" --output "$NOTE_PATH"

"$APPEND_LEDGER" \
  --ledger-path "$LEDGER_PATH" \
  --run-url "$RUN_URL" \
  --policy "$POLICY" \
  --outcome "$OUTCOME" \
  --s4-softfail-evidence "$SOFTFAIL_EVIDENCE" \
  --artifact-dir "$ARTIFACT_DIR" \
  --artifact-ref "$ARTIFACT_REF" \
  --note-path "$NOTE_PATH"

"$RENDER_SUMMARY" --ledger-path "$LEDGER_PATH" --last "$LAST_N" > "$SUMMARY_PATH"

echo "[info] checkpoint note: $NOTE_PATH"
echo "[info] checkpoint ledger: $LEDGER_PATH"
echo "[info] checkpoint summary: $SUMMARY_PATH"
