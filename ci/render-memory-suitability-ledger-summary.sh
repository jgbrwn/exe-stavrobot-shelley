#!/usr/bin/env bash
set -euo pipefail

LEDGER_PATH=""
LAST_N=10

usage() {
  cat <<'USAGE'
Usage: ./ci/render-memory-suitability-ledger-summary.sh --ledger-path PATH [--last N]

Render a markdown summary table from checkpoint ledger JSON.

Flags:
  --ledger-path PATH   Ledger JSON path
  --last N             Render only last N entries (default: 10)
  --help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ledger-path)
      LEDGER_PATH="$2"
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

[[ -n "$LEDGER_PATH" ]] || { echo "[error] --ledger-path is required" >&2; exit 1; }
[[ -f "$LEDGER_PATH" ]] || { echo "[error] Ledger not found: $LEDGER_PATH" >&2; exit 1; }
[[ "$LAST_N" =~ ^[0-9]+$ ]] || { echo "[error] --last must be a non-negative integer" >&2; exit 1; }

python3 - "$LEDGER_PATH" "$LAST_N" <<'PY'
import json
import sys

ledger_path, last_n_raw = sys.argv[1:]
last_n = int(last_n_raw)

with open(ledger_path, "r", encoding="utf-8") as f:
    data = json.load(f)

if not isinstance(data, dict) or not isinstance(data.get("checkpoints"), list):
    raise SystemExit(f"[error] invalid ledger structure: {ledger_path}")

rows = data["checkpoints"]
if last_n > 0:
    rows = rows[-last_n:]

def short(v):
    if not v:
        return "-"
    s = str(v)
    return s.replace("|", "\\|")

print("### Memory-suitability required-runtime local run history (last %d)" % (last_n,))
print("")
print("| created_at_utc | outcome | policy | s4_softfail_evidence | run_ref | artifact_ref | git_head |")
print("|---|---|---|---|---|---|---|")
for e in rows:
    run_ref = e.get("run_ref", "")
    run_cell = short(run_ref)
    if run_ref.startswith("http://") or run_ref.startswith("https://"):
        run_cell = f"[link]({run_ref})"
    git_head = e.get("git_head", "")
    if git_head:
        git_head = git_head[:12]
    print(
        "| %s | %s | %s | %s | %s | %s | %s |"
        % (
            short(e.get("created_at_utc")),
            short(e.get("outcome")),
            short(e.get("policy")),
            short(e.get("s4_softfail_evidence")),
            run_cell,
            short(e.get("artifact_ref")),
            short(git_head),
        )
    )
PY
