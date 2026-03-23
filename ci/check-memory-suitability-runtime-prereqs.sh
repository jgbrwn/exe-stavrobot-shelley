#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SHELLEY_DIR="${SHELLEY_DIR:-/opt/shelley}"
PROFILE_STATE_PATH="${PROFILE_STATE_PATH:-$ROOT_DIR/state/shelley-bridge-profiles.json}"
JSON=0

usage() {
  cat <<'USAGE'
Usage: ./ci/check-memory-suitability-runtime-prereqs.sh [flags]

Preflight checker for the required-runtime memory-suitability CI lane.

Checks:
  - managed Shelley binary exists and is executable
  - profile-state file exists
  - local Stavrobot config exists at /tmp/stavrobot/data/main/config.toml

Flags:
  --shelley-dir PATH         Override SHELLEY_DIR (default: /opt/shelley)
  --profile-state-path PATH  Override PROFILE_STATE_PATH (default: ./state/shelley-bridge-profiles.json)
  --json                     Emit machine-readable JSON summary
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
    --json)
      JSON=1
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

shelley_bin="$SHELLEY_DIR/bin/shelley"
stavrobot_cfg="/tmp/stavrobot/data/main/config.toml"

ok=1
missing=()

if [[ ! -x "$shelley_bin" ]]; then
  ok=0
  missing+=("managed_shelley_binary:$shelley_bin")
fi
if [[ ! -f "$PROFILE_STATE_PATH" ]]; then
  ok=0
  missing+=("profile_state:$PROFILE_STATE_PATH")
fi
if [[ ! -f "$stavrobot_cfg" ]]; then
  ok=0
  missing+=("stavrobot_config:$stavrobot_cfg")
fi

if (( JSON == 1 )); then
  python3 - "$ok" "$shelley_bin" "$PROFILE_STATE_PATH" "$stavrobot_cfg" "${missing[*]:-}" <<'PY'
import json, sys
ok = sys.argv[1] == '1'
out = {
    "ok": ok,
    "shelley_bin": sys.argv[2],
    "profile_state_path": sys.argv[3],
    "stavrobot_config": sys.argv[4],
    "missing": [x for x in sys.argv[5].split() if x],
}
print(json.dumps(out, sort_keys=True))
PY
else
  echo "[info] SHELLEY_DIR=$SHELLEY_DIR"
  echo "[info] PROFILE_STATE_PATH=$PROFILE_STATE_PATH"
  echo "[info] Expecting Stavrobot config at $stavrobot_cfg"
  if (( ok == 1 )); then
    echo "[info] required-runtime memory-suitability preflight passed"
  else
    echo "[error] required-runtime memory-suitability preflight failed" >&2
    for item in "${missing[@]}"; do
      echo "[error] missing: $item" >&2
    done
  fi
fi

if (( ok == 0 )); then
  exit 1
fi
