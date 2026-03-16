#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

STAVROBOT_DIR=""
CONFIG_PATH=""
BASE_URL="http://localhost:10567"
PASSWORD=""
MESSAGE=""
SOURCE=""
SENDER=""
RAW_JSON=0

usage() {
  cat <<'EOF'
Usage: ./chat-with-stavrobot.sh [flags]

Flags:
  --stavrobot-dir PATH   Read password from PATH/data/main/config.toml
  --config-path PATH     Read password from config.toml
  --base-url URL         Stavrobot base URL (default: http://localhost:10567)
  --password VALUE       Override password directly
  --message TEXT         Message to send; if omitted, read stdin
  --source NAME          Optional source field for /chat
  --sender NAME          Optional sender field for /chat
  --raw-json             Print raw JSON response
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

read_message() {
  if [[ -n "$MESSAGE" ]]; then
    return 0
  fi
  if [[ -t 0 ]]; then
    die "Provide --message or pipe message text on stdin"
  fi
  MESSAGE=$(cat)
}

build_payload() {
  python3 - "$MESSAGE" "$SOURCE" "$SENDER" <<'PY'
import json, sys
payload = {"message": sys.argv[1]}
if sys.argv[2]:
    payload["source"] = sys.argv[2]
if sys.argv[3]:
    payload["sender"] = sys.argv[3]
print(json.dumps(payload))
PY
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
    --source)
      SOURCE="$2"
      shift 2
      ;;
    --sender)
      SENDER="$2"
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
require_cmd curl
resolve_config_path
load_password_from_config
read_message
[[ -n "$PASSWORD" ]] || die "Could not determine Stavrobot password"

PAYLOAD=$(build_payload)
RESPONSE=$(curl -fsS -u "installer:$PASSWORD" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD" \
  "$BASE_URL/chat")

if (( RAW_JSON )); then
  printf '%s\n' "$RESPONSE"
else
  python3 -c 'import json,sys; print(json.load(sys.stdin).get("response", ""))' <<<"$RESPONSE"
fi
