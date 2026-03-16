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
CONNECT_TIMEOUT=10
REQUEST_TIMEOUT=300
RETRIES=1
RETRY_DELAY=2
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
  --connect-timeout SEC  Curl connect timeout in seconds (default: 10)
  --request-timeout SEC  Total request timeout in seconds (default: 300)
  --retries COUNT        Retry count on transport failure (default: 1)
  --retry-delay SEC      Sleep between retries (default: 2)
  --raw-json             Print raw JSON response
  --help
EOF
}

json_quote() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

resolve_config_path() {
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

request_once() {
  local payload="$1"
  local body_file http_code
  body_file=$(mktemp)
  http_code=$(curl -sS \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$REQUEST_TIMEOUT" \
    -u "installer:$PASSWORD" \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    -o "$body_file" \
    -w '%{http_code}' \
    "$BASE_URL/chat") || {
      rm -f "$body_file"
      return 2
    }
  printf '%s\n%s\n' "$http_code" "$body_file"
}

perform_request() {
  local payload="$1"
  local attempt=1
  local result http_code body_file
  while (( attempt <= RETRIES )); do
    result=$(request_once "$payload") || {
      if (( attempt == RETRIES )); then
        return 2
      fi
      warn "Transport failure talking to Stavrobot; retrying ($attempt/$RETRIES)"
      sleep "$RETRY_DELAY"
      ((attempt+=1))
      continue
    }
    http_code=$(printf '%s' "$result" | sed -n '1p')
    body_file=$(printf '%s' "$result" | sed -n '2p')
    if [[ "$http_code" =~ ^2 ]]; then
      cat "$body_file"
      rm -f "$body_file"
      return 0
    fi
    warn "Stavrobot returned HTTP $http_code"
    cat "$body_file" >&2
    rm -f "$body_file"
    return 1
  done
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
    --connect-timeout)
      CONNECT_TIMEOUT="$2"
      shift 2
      ;;
    --request-timeout)
      REQUEST_TIMEOUT="$2"
      shift 2
      ;;
    --retries)
      RETRIES="$2"
      shift 2
      ;;
    --retry-delay)
      RETRY_DELAY="$2"
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
[[ "$CONNECT_TIMEOUT" =~ ^[0-9]+$ ]] || die "--connect-timeout must be an integer"
[[ "$REQUEST_TIMEOUT" =~ ^[0-9]+$ ]] || die "--request-timeout must be an integer"
[[ "$RETRIES" =~ ^[0-9]+$ ]] || die "--retries must be an integer"
[[ "$RETRY_DELAY" =~ ^[0-9]+$ ]] || die "--retry-delay must be an integer"
(( RETRIES >= 1 )) || die "--retries must be at least 1"

PAYLOAD=$(build_payload)
if ! RESPONSE=$(perform_request "$PAYLOAD"); then
  status=$?
  if (( status == 2 )); then
    die "Could not reach Stavrobot at $BASE_URL"
  fi
  die "Stavrobot request failed"
fi

if (( RAW_JSON )); then
  printf '%s\n' "$RESPONSE"
else
  python3 -c 'import json,sys; print(json.load(sys.stdin).get("response", ""))' <<<"$RESPONSE"
fi
