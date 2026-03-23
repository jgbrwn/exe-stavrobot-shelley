#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR=""
REPO_DIR="$(pwd)"

S4_SERVER_LOG_PATH="${S4_SERVER_LOG_PATH:-/tmp/shelley-s4-recall-validation.log}"
S4_RUNTIME_CONTRACT_JSON_PATH="${S4_RUNTIME_CONTRACT_JSON_PATH:-/tmp/s4-runtime-contract.json}"
S4_LAST_REPORT_PATH="${S4_LAST_REPORT_PATH:-$REPO_DIR/state/s4-recall-validation-last.json}"

usage() {
  cat <<'USAGE'
Usage: ./ci/collect-memory-suitability-artifacts.sh --output-dir PATH [--repo-dir PATH]

Collects lightweight diagnostics/artifacts for the required-runtime memory-suitability CI lane.

Inputs (defaults can be overridden via env vars):
  S4_SERVER_LOG_PATH             /tmp/shelley-s4-recall-validation.log
  S4_RUNTIME_CONTRACT_JSON_PATH  /tmp/s4-runtime-contract.json
  S4_LAST_REPORT_PATH            <repo>/state/s4-recall-validation-last.json
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --repo-dir)
      REPO_DIR="$2"
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

if [[ -z "$OUTPUT_DIR" ]]; then
  echo "[error] --output-dir is required" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
manifest="$OUTPUT_DIR/manifest.txt"
: > "$manifest"

copy_if_exists() {
  local src="$1"
  local name="$2"
  if [[ -f "$src" ]]; then
    cp "$src" "$OUTPUT_DIR/$name"
    echo "$name <= $src" >> "$manifest"
  fi
}

copy_if_exists "$S4_SERVER_LOG_PATH" "s4-server.log"
copy_if_exists "$S4_RUNTIME_CONTRACT_JSON_PATH" "s4-runtime-contract.json"
copy_if_exists "$S4_LAST_REPORT_PATH" "s4-last-report.json"

{
  echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "repo_dir=$REPO_DIR"
  echo "pwd=$(pwd)"
  echo "git_head=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "\n## docker ps"
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
  echo "\n## listeners (8000/8926/9999)"
  ss -ltnp 2>/dev/null | rg ':8000|:8926|:9999' || true
} > "$OUTPUT_DIR/diagnostics.txt"

echo "diagnostics.txt <= generated" >> "$manifest"

echo "[info] collected artifacts into $OUTPUT_DIR"
