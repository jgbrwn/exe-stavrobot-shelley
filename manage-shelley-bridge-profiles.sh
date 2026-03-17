#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
PYTHON_BIN="${PYTHON_BIN:-python3}"
PROFILE_STATE_PATH="${PROFILE_STATE_PATH:-$ROOT_DIR/state/shelley-bridge-profiles.json}"

usage() {
  cat <<'EOF'
Usage: ./manage-shelley-bridge-profiles.sh <print-default-path|validate|resolve> [flags]

Commands:
  print-default-path              Print the default managed profile-state path
  validate                        Validate the profile-state file
  resolve                         Resolve one profile or the default profile

Flags:
  --profile-state-path PATH       Profile-state file path
  --profile-name NAME             Profile name for resolve
  --help
EOF
}

COMMAND=""
PROFILE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    print-default-path|validate|resolve)
      [[ -z "$COMMAND" ]] || {
        echo "duplicate command: $1" >&2
        exit 1
      }
      COMMAND="$1"
      shift
      ;;
    --profile-state-path)
      PROFILE_STATE_PATH="$2"
      shift 2
      ;;
    --profile-name)
      PROFILE_NAME="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "$COMMAND" ]] || {
  usage >&2
  exit 1
}

case "$COMMAND" in
  print-default-path)
    exec "$PYTHON_BIN" "$ROOT_DIR/py/shelley_bridge_profiles.py" print-default-path
    ;;
  validate)
    exec "$PYTHON_BIN" "$ROOT_DIR/py/shelley_bridge_profiles.py" validate "$PROFILE_STATE_PATH"
    ;;
  resolve)
    if [[ -n "$PROFILE_NAME" ]]; then
      exec "$PYTHON_BIN" "$ROOT_DIR/py/shelley_bridge_profiles.py" resolve "$PROFILE_STATE_PATH" "$PROFILE_NAME"
    fi
    exec "$PYTHON_BIN" "$ROOT_DIR/py/shelley_bridge_profiles.py" resolve "$PROFILE_STATE_PATH"
    ;;
esac
