#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

STAVROBOT_DIR=""
CONFIG_PATH=""
BASE_URL="${STAVROBOT_BASE_URL:-http://localhost:8000}"
PASSWORD=""
COMMAND=""
MESSAGE=""
CONVERSATION_ID=""
SOURCE=""
SENDER=""
CONNECT_TIMEOUT=10
REQUEST_TIMEOUT=300
RETRIES=1
RETRY_DELAY=2
PRETTY=0
EXTRACT=""

usage() {
  cat <<'EOF'
Usage: ./client-stavrobot.sh <command> [flags]

Commands:
  health                         GET /api/client/health
  chat                           POST /api/client/chat
  conversations                  GET /api/client/conversations
  messages --conversation-id ID  GET /api/client/conversations/:id/messages
  events --conversation-id ID    GET /api/client/conversations/:id/events

Flags:
  --stavrobot-dir PATH   Read password from PATH/data/main/config.toml
  --config-path PATH     Read password from config.toml
  --base-url URL         Stavrobot base URL (default: STAVROBOT_BASE_URL or http://localhost:8000)
  --password VALUE       Override password directly
  --message TEXT         Message to send for chat; if omitted, read stdin
  --conversation-id ID   Existing conversation for chat/messages/events
  --source NAME          Optional source field for client chat
  --sender NAME          Optional sender field for client chat
  --connect-timeout SEC  Curl connect timeout in seconds (default: 10)
  --request-timeout SEC  Total request timeout in seconds (default: 300)
  --retries COUNT        Retry count on transport failure (default: 1)
  --retry-delay SEC      Sleep between retries (default: 2)
  --pretty               Pretty-print JSON output
  --extract FIELD        Print only one extracted field
  --help

Extract fields:
  response
  conversation_id
  message_id
  ok
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

read_message_if_needed() {
  [[ "$COMMAND" == "chat" ]] || return 0
  if [[ -n "$MESSAGE" ]]; then
    return 0
  fi
  if [[ -t 0 ]]; then
    die "Provide --message or pipe message text on stdin"
  fi
  MESSAGE=$(cat)
}

build_chat_payload() {
  python3 - "$MESSAGE" "$CONVERSATION_ID" "$SOURCE" "$SENDER" <<'PY'
import json, sys
payload = {"message": sys.argv[1]}
if sys.argv[2]:
    payload["conversation_id"] = sys.argv[2]
if sys.argv[3]:
    payload["source"] = sys.argv[3]
if sys.argv[4]:
    payload["sender"] = sys.argv[4]
print(json.dumps(payload))
PY
}

build_request() {
  case "$COMMAND" in
    health)
      REQUEST_METHOD="GET"
      REQUEST_PATH="/api/client/health"
      REQUEST_BODY=""
      ;;
    chat)
      REQUEST_METHOD="POST"
      REQUEST_PATH="/api/client/chat"
      REQUEST_BODY=$(build_chat_payload)
      ;;
    conversations)
      REQUEST_METHOD="GET"
      REQUEST_PATH="/api/client/conversations"
      REQUEST_BODY=""
      ;;
    messages)
      [[ -n "$CONVERSATION_ID" ]] || die "--conversation-id is required for messages"
      REQUEST_METHOD="GET"
      REQUEST_PATH="/api/client/conversations/$CONVERSATION_ID/messages"
      REQUEST_BODY=""
      ;;
    events)
      [[ -n "$CONVERSATION_ID" ]] || die "--conversation-id is required for events"
      REQUEST_METHOD="GET"
      REQUEST_PATH="/api/client/conversations/$CONVERSATION_ID/events"
      REQUEST_BODY=""
      ;;
    *)
      die "Unknown command: $COMMAND"
      ;;
  esac
}

request_once() {
  local body_file http_code curl_args=()
  body_file=$(mktemp)
  if [[ -n "$REQUEST_BODY" ]]; then
    curl_args=(-H 'Content-Type: application/json' -d "$REQUEST_BODY")
  fi
  http_code=$(curl -sS \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$REQUEST_TIMEOUT" \
    -u "installer:$PASSWORD" \
    -X "$REQUEST_METHOD" \
    "${curl_args[@]}" \
    -o "$body_file" \
    -w '%{http_code}' \
    "$BASE_URL$REQUEST_PATH") || {
      rm -f "$body_file"
      return 2
    }
  printf '%s\n%s\n' "$http_code" "$body_file"
}

perform_request() {
  local attempt=1
  local result http_code body_file
  while (( attempt <= RETRIES )); do
    result=$(request_once) || {
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
    health|chat|conversations|messages|events)
      [[ -z "$COMMAND" ]] || die "Only one command may be specified"
      COMMAND="$1"
      shift
      ;;
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
    --conversation-id)
      CONVERSATION_ID="$2"
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
    --pretty)
      PRETTY=1
      shift
      ;;
    --extract)
      EXTRACT="$2"
      shift 2
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
[[ -n "$COMMAND" ]] || {
  usage >&2
  die "Missing command"
}
resolve_config_path
load_password_from_config
read_message_if_needed
[[ -n "$PASSWORD" ]] || die "Could not determine Stavrobot password"
[[ "$CONNECT_TIMEOUT" =~ ^[0-9]+$ ]] || die "--connect-timeout must be an integer"
[[ "$REQUEST_TIMEOUT" =~ ^[0-9]+$ ]] || die "--request-timeout must be an integer"
[[ "$RETRIES" =~ ^[0-9]+$ ]] || die "--retries must be an integer"
[[ "$RETRY_DELAY" =~ ^[0-9]+$ ]] || die "--retry-delay must be an integer"
(( RETRIES >= 1 )) || die "--retries must be at least 1"
if (( PRETTY )) && [[ -n "$EXTRACT" ]]; then
  die "--pretty and --extract cannot be combined"
fi
build_request

if RESPONSE=$(perform_request); then
  :
else
  status=$?
  if (( status == 2 )); then
    die "Could not reach Stavrobot at $BASE_URL"
  fi
  die "Stavrobot request failed"
fi

if [[ -n "$EXTRACT" ]]; then
  python3 - "$EXTRACT" "$RESPONSE" <<'PY'
import json, sys
field, response_json = sys.argv[1:3]
data = json.loads(response_json)
value = data.get(field, '')
if isinstance(value, bool):
    print('true' if value else 'false')
elif value is None:
    print('')
elif isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
elif (( PRETTY )); then
  python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), indent=2, sort_keys=True))' <<<"$RESPONSE"
else
  printf '%s\n' "$RESPONSE"
fi
