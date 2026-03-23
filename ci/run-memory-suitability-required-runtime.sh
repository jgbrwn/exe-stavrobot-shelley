#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
GATE_RUNNER="$ROOT_DIR/run-shelley-managed-memory-suitability-gate.sh"
SHELLEY_DIR="${SHELLEY_DIR:-/opt/shelley}"
PROFILE_STATE_PATH="${PROFILE_STATE_PATH:-$ROOT_DIR/state/shelley-bridge-profiles.json}"
RUN_FULL_SUITE=0
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: ./ci/run-memory-suitability-required-runtime.sh [flags]

Authoritative CI entrypoint for required-runtime managed memory-suitability evidence hygiene.

Runs:
  ./run-shelley-managed-memory-suitability-gate.sh \
    --required-runtime \
    --shelley-dir <path> \
    --profile-state-path <path>

Flags:
  --shelley-dir PATH         Override SHELLEY_DIR (default: /opt/shelley)
  --profile-state-path PATH  Override PROFILE_STATE_PATH (default: ./state/shelley-bridge-profiles.json)
  --full-suite               Also run full helper/status suite after gate lane
  --dry-run                  Print planned gate command only
  --help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shelley-dir)
      SHELLEY_DIR="$2"
      shift 2
      ;;
    --profile-state-path)
      PROFILE_STATE_PATH="$2"
      shift 2
      ;;
    --full-suite)
      RUN_FULL_SUITE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
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

if [[ ! -x "$GATE_RUNNER" ]]; then
  echo "[error] Missing executable gate runner: $GATE_RUNNER" >&2
  exit 1
fi

cmd=(
  "$GATE_RUNNER"
  --required-runtime
  --shelley-dir "$SHELLEY_DIR"
  --profile-state-path "$PROFILE_STATE_PATH"
)
if (( RUN_FULL_SUITE == 1 )); then
  cmd+=(--full-suite)
fi

if (( DRY_RUN == 1 )); then
  printf '[dry-run] '
  printf '%q ' "${cmd[@]}"
  printf '\n'
  exit 0
fi

"${cmd[@]}"
