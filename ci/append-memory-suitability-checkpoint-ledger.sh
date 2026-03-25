#!/usr/bin/env bash
set -euo pipefail

LEDGER_PATH=""
RUN_REF=""
RUN_URL=""
POLICY="strict"
OUTCOME=""
SOFTFAIL_EVIDENCE="unknown"
ARTIFACT_DIR=""
ARTIFACT_REF=""
NOTE_PATH=""
ALLOW_DUPLICATE=0

usage() {
  cat <<'USAGE'
Usage: ./ci/append-memory-suitability-checkpoint-ledger.sh --ledger-path PATH --run-ref TEXT --outcome pass|fail --artifact-dir PATH [flags]

Append one memory-suitability checkpoint row to an append-only JSON ledger.

Required:
  --ledger-path PATH              Ledger JSON file to append/create
  --run-ref TEXT                  Local run reference label (or URL)
  --outcome STATUS                STATUS=pass|fail
  --artifact-dir PATH             Artifact directory used for this checkpoint

Optional:
  --policy MODE                   MODE=allow|strict (default: strict)
  --s4-softfail-evidence STATE    STATE=yes|no|unknown (default: unknown)
  --artifact-ref TEXT             Artifact handle/name (default: basename(artifact-dir))
  --note-path PATH                Rendered checkpoint note path
  --allow-duplicate               Allow duplicate run_ref+artifact_ref entries
  --help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ledger-path)
      LEDGER_PATH="$2"
      shift 2
      ;;
    --run-ref)
      RUN_REF="$2"
      shift 2
      ;;
    --run-url)
      RUN_URL="$2"
      RUN_REF="$2"
      shift 2
      ;;
    --policy)
      POLICY="$2"
      shift 2
      ;;
    --outcome)
      OUTCOME="$2"
      shift 2
      ;;
    --s4-softfail-evidence)
      SOFTFAIL_EVIDENCE="$2"
      shift 2
      ;;
    --artifact-dir)
      ARTIFACT_DIR="$2"
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
    --allow-duplicate)
      ALLOW_DUPLICATE=1
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

[[ -n "$LEDGER_PATH" ]] || { echo "[error] --ledger-path is required" >&2; exit 1; }
if [[ -z "$RUN_REF" ]]; then
  echo "[error] --run-ref is required" >&2
  echo "[error] --run-url is supported as a backward-compatible alias" >&2
  exit 1
fi
[[ -n "$OUTCOME" ]] || { echo "[error] --outcome is required" >&2; exit 1; }
[[ -n "$ARTIFACT_DIR" ]] || { echo "[error] --artifact-dir is required" >&2; exit 1; }
[[ -d "$ARTIFACT_DIR" ]] || { echo "[error] Artifact dir not found: $ARTIFACT_DIR" >&2; exit 1; }

if [[ "$POLICY" != "allow" && "$POLICY" != "strict" ]]; then
  echo "[error] --policy must be allow or strict" >&2
  exit 1
fi
if [[ "$OUTCOME" != "pass" && "$OUTCOME" != "fail" ]]; then
  echo "[error] --outcome must be pass or fail" >&2
  exit 1
fi
if [[ "$SOFTFAIL_EVIDENCE" != "yes" && "$SOFTFAIL_EVIDENCE" != "no" && "$SOFTFAIL_EVIDENCE" != "unknown" ]]; then
  echo "[error] --s4-softfail-evidence must be yes, no, or unknown" >&2
  exit 1
fi

if [[ -z "$ARTIFACT_REF" ]]; then
  ARTIFACT_REF="$(basename "$ARTIFACT_DIR")"
fi

diag_stamp=""
git_head=""
if [[ -f "$ARTIFACT_DIR/diagnostics.txt" ]]; then
  diag_stamp=$(awk -F= '/^timestamp=/{print $2; exit}' "$ARTIFACT_DIR/diagnostics.txt" || true)
  git_head=$(awk -F= '/^git_head=/{print $2; exit}' "$ARTIFACT_DIR/diagnostics.txt" || true)
fi

mkdir -p "$(dirname "$LEDGER_PATH")"

python3 - "$LEDGER_PATH" "$RUN_REF" "$POLICY" "$OUTCOME" "$SOFTFAIL_EVIDENCE" "$ARTIFACT_DIR" "$ARTIFACT_REF" "$diag_stamp" "$git_head" "$NOTE_PATH" "$ALLOW_DUPLICATE" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

(
    ledger_path,
    run_ref,
    policy,
    outcome,
    softfail,
    artifact_dir,
    artifact_ref,
    diagnostics_ts,
    git_head,
    note_path,
    allow_duplicate_raw,
) = sys.argv[1:]
allow_duplicate = allow_duplicate_raw == "1"

entry = {
    "created_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "run_ref": run_ref,
    "policy": policy,
    "outcome": outcome,
    "s4_softfail_evidence": softfail,
    "artifact_dir": artifact_dir,
    "artifact_ref": artifact_ref,
}
if diagnostics_ts:
    entry["diagnostics_timestamp_utc"] = diagnostics_ts
if git_head:
    entry["git_head"] = git_head
if note_path:
    entry["note_path"] = note_path

if os.path.exists(ledger_path):
    with open(ledger_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict) or not isinstance(data.get("checkpoints"), list):
        raise SystemExit(f"[error] invalid ledger structure: {ledger_path}")
else:
    data = {"schema_version": 1, "checkpoints": []}

if not allow_duplicate:
    for existing in data["checkpoints"]:
        if (
            existing.get("run_ref") == run_ref
            and existing.get("artifact_ref") == artifact_ref
        ):
            raise SystemExit(
                "[error] duplicate checkpoint (same run_ref + artifact_ref); use --allow-duplicate to override"
            )

data["checkpoints"].append(entry)

with open(ledger_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")

print(f"[info] appended checkpoint to {ledger_path}")
print(f"[info] total checkpoints: {len(data['checkpoints'])}")
PY
