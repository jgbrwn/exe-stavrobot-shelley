#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

PRECHECK_CMD="${MEMORY_SUITABILITY_PRECHECK_CMD:-$ROOT_DIR/ci/check-memory-suitability-runtime-prereqs.sh}"
GATE_CMD="${MEMORY_SUITABILITY_GATE_CMD:-$ROOT_DIR/ci/run-memory-suitability-required-runtime.sh}"
COLLECT_CMD="${MEMORY_SUITABILITY_COLLECT_CMD:-$ROOT_DIR/ci/collect-memory-suitability-artifacts.sh}"
RECORD_CMD="${MEMORY_SUITABILITY_RECORD_CMD:-$ROOT_DIR/ci/record-memory-suitability-checkpoint.sh}"

SHELLEY_DIR="${SHELLEY_DIR:-/opt/shelley}"
PROFILE_STATE_PATH="${PROFILE_STATE_PATH:-$ROOT_DIR/state/shelley-bridge-profiles.json}"
POLICY="${S4_SOFTFAIL_POLICY:-strict}"
ARTIFACT_ROOT_DIR="${ARTIFACT_ROOT_DIR:-$ROOT_DIR/state}"
RUN_REF=""
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: ./ci/run-memory-suitability-local-checkpoint.sh [flags]

Run local required-runtime checkpoint flow:
  1) preflight
  2) required-runtime gate
  3) artifact collection
  4) checkpoint note + ledger + summary update

Flags:
  --shelley-dir PATH         Override SHELLEY_DIR (default: /opt/shelley)
  --profile-state-path PATH  Override PROFILE_STATE_PATH
  --policy MODE              MODE=allow|strict (default: strict)
  --artifact-root-dir PATH   Root dir for timestamped artifact bundle (default: ./state)
  --run-ref TEXT             Local run reference label (default: local:<ts>-required-runtime-gate)
  --dry-run                  Print planned commands only
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
    --policy)
      POLICY="$2"
      shift 2
      ;;
    --artifact-root-dir)
      ARTIFACT_ROOT_DIR="$2"
      shift 2
      ;;
    --run-ref)
      RUN_REF="$2"
      shift 2
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

if [[ "$POLICY" != "allow" && "$POLICY" != "strict" ]]; then
  echo "[error] --policy must be allow or strict" >&2
  exit 1
fi

ts=$(date -u +%Y%m%dT%H%M%SZ)
if [[ -z "$RUN_REF" ]]; then
  RUN_REF="local:${ts}-required-runtime-gate"
fi
ARTIFACT_DIR="$ARTIFACT_ROOT_DIR/ci-artifacts-memory-suitability-$ts"

pre_cmd=("$PRECHECK_CMD" --shelley-dir "$SHELLEY_DIR" --profile-state-path "$PROFILE_STATE_PATH")
gate_cmd=("$GATE_CMD" --shelley-dir "$SHELLEY_DIR" --profile-state-path "$PROFILE_STATE_PATH" --s4-softfail-policy "$POLICY")
collect_cmd=("$COLLECT_CMD" --output-dir "$ARTIFACT_DIR" --repo-dir "$ROOT_DIR")
record_cmd=("$RECORD_CMD" --artifact-dir "$ARTIFACT_DIR" --run-ref "$RUN_REF" --policy "$POLICY")

if (( DRY_RUN == 1 )); then
  echo "[dry-run] run_ref=$RUN_REF"
  echo "[dry-run] artifact_dir=$ARTIFACT_DIR"
  printf '[dry-run] '; printf '%q ' "${pre_cmd[@]}"; printf '\n'
  printf '[dry-run] '; printf '%q ' "${gate_cmd[@]}"; printf '\n'
  printf '[dry-run] '; printf '%q ' "${collect_cmd[@]}"; printf '\n'
  printf '[dry-run] '; printf '%q ' "${record_cmd[@]}"; printf ' --outcome <pass|fail> --s4-softfail-evidence <yes|no|unknown>\n'
  exit 0
fi

mkdir -p "$ARTIFACT_DIR"

pre_status=0
gate_status=0
collect_status=0
record_status=0

set +e
"${pre_cmd[@]}"
pre_status=$?
set -e
if (( pre_status != 0 )); then
  echo "[warn] preflight failed" >&2
fi

if (( pre_status == 0 )); then
  set +e
  "${gate_cmd[@]}"
  gate_status=$?
  set -e
  if (( gate_status != 0 )); then
    echo "[warn] required-runtime gate failed" >&2
  fi
else
  echo "[info] skipping gate run because preflight failed" >&2
fi

set +e
"${collect_cmd[@]}"
collect_status=$?
set -e
if (( collect_status != 0 )); then
  echo "[warn] artifact collection failed" >&2
fi

softfail_evidence="unknown"
report_path="$ARTIFACT_DIR/s4-last-report.json"
if [[ -f "$report_path" ]]; then
  if python3 - "$report_path" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception:
    sys.exit(2)

def has_softfail(v):
    if isinstance(v, dict):
        if v.get('bridge_softfail') == 'context_overflow':
            return True
        return any(has_softfail(x) for x in v.values())
    if isinstance(v, list):
        return any(has_softfail(x) for x in v)
    return False

sys.exit(0 if has_softfail(data) else 1)
PY
  then
    softfail_evidence="yes"
  else
    rc=$?
    if [[ $rc -eq 1 ]]; then
      softfail_evidence="no"
    else
      softfail_evidence="unknown"
    fi
  fi
fi

outcome="pass"
if (( pre_status != 0 || gate_status != 0 || collect_status != 0 )); then
  outcome="fail"
fi

set +e
"${record_cmd[@]}" --outcome "$outcome" --s4-softfail-evidence "$softfail_evidence"
record_status=$?
set -e
if (( record_status != 0 )); then
  echo "[warn] checkpoint recording failed" >&2
fi

if (( pre_status != 0 || gate_status != 0 || collect_status != 0 || record_status != 0 )); then
  exit 1
fi

echo "[info] local memory-suitability checkpoint completed"
