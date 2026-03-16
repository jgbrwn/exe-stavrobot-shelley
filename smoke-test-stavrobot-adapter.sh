#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

STAVROBOT_DIR=""
CONFIG_PATH=""
BASE_URL="${STAVROBOT_BASE_URL:-http://localhost:8000}"
PASSWORD=""
MESSAGE="Reply with exactly: adapter smoke test ok"
SOURCE="shelley-smoke"
SENDER="installer"
TIMEOUT=60
RAW_JSON=0

usage() {
  cat <<'EOF'
Usage: ./smoke-test-stavrobot-adapter.sh [flags]

Flags:
  --stavrobot-dir PATH   Read password from PATH/data/main/config.toml
  --config-path PATH     Read password from config.toml
  --base-url URL         Stavrobot base URL (default: STAVROBOT_BASE_URL or http://localhost:8000)
  --password VALUE       Override password directly
  --message TEXT         Test message to send
  --timeout SEC          End-to-end timeout in seconds (default: 60)
  --raw-json             Print raw adapter JSON response
  --help
EOF
}

resolve_config_path() {
  if [[ -z "$CONFIG_PATH" && -n "$STAVROBOT_DIR" ]]; then
    CONFIG_PATH="$STAVROBOT_DIR/data/main/config.toml"
  fi
}

load_password_from_config() {
  [[ -n "$PASSWORD" ]] && return 0
  [[ -n "$CONFIG_PATH" ]] || return 0
  [[ -f "$CONFIG_PATH" ]] || die "Config file not found: $CONFIG_PATH"
  PASSWORD=$(python3 - "$CONFIG_PATH" <<'PY'
import sys, tomllib
try:
    data = tomllib.loads(open(sys.argv[1]).read())
    print(data.get('password', ''))
except Exception:
    print('')
PY
)
}

run_smoke() {
  local -a cmd
  cmd=(
    "$ROOT_DIR/chat-with-stavrobot.sh"
    --base-url "$BASE_URL"
    --message "$MESSAGE"
    --source "$SOURCE"
    --sender "$SENDER"
    --connect-timeout 10
    --request-timeout "$TIMEOUT"
    --retries 2
    --retry-delay 2
  )
  if [[ -n "$STAVROBOT_DIR" ]]; then
    cmd+=(--stavrobot-dir "$STAVROBOT_DIR")
  fi
  if [[ -n "$CONFIG_PATH" ]]; then
    cmd+=(--config-path "$CONFIG_PATH")
  fi
  if [[ -n "$PASSWORD" ]]; then
    cmd+=(--password "$PASSWORD")
  fi
  if (( RAW_JSON )); then
    cmd+=(--raw-json)
  fi
  "${cmd[@]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stavrobot-dir)
      STAVROBOT_DIR="$2"
      shift 2
      ;;
    --config-path)
      CONFIG_PATH="$2"
      shift 2
      ;;
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    --message)
      MESSAGE="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --raw-json)
      RAW_JSON=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

require_cmd python3
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die "--timeout must be an integer"
resolve_config_path
load_password_from_config
[[ -n "$PASSWORD" ]] || die "Could not determine Stavrobot password"

info "Running Shelley adapter smoke test against $BASE_URL"
RESULT=$(run_smoke)

if (( RAW_JSON )); then
  printf '%s\n' "$RESULT"
else
  printf 'Adapter response:\n%s\n' "$RESULT"
fi

info "Smoke test completed"
