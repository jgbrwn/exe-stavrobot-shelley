#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

STAVROBOT_DIR=""
CONFIG_PATH=""
BASE_URL="${STAVROBOT_BASE_URL:-http://localhost:8000}"
PASSWORD=""
MESSAGE="Reply with exactly: client smoke test ok"
SOURCE="shelley-client-smoke"
SENDER="installer"
TIMEOUT=60
PRETTY=0

usage() {
  cat <<'EOF'
Usage: ./smoke-test-stavrobot-client.sh [flags]

Flags:
  --stavrobot-dir PATH   Read password from PATH/data/main/config.toml
  --config-path PATH     Read password from config.toml
  --base-url URL         Stavrobot base URL (default: STAVROBOT_BASE_URL or http://localhost:8000)
  --password VALUE       Override password directly
  --message TEXT         Test message to send
  --timeout SEC          End-to-end timeout in seconds (default: 60)
  --pretty               Pretty-print JSON output
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

run_client() {
  local -a cmd
  cmd=(
    "$ROOT_DIR/client-stavrobot.sh"
    --base-url "$BASE_URL"
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
  if (( PRETTY )); then
    cmd+=(--pretty)
  fi
  "${cmd[@]}" "$@"
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
    --pretty)
      PRETTY=1
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

info "Checking client health at $BASE_URL"
HEALTH=$(run_client health)
python3 -c 'import json,sys; data=json.load(sys.stdin); assert data.get("ok") is True, data' <<<"$HEALTH" >/dev/null

info "Creating or continuing client conversation"
CHAT=$(run_client chat --message "$MESSAGE" --source "$SOURCE" --sender "$SENDER")
CONVERSATION_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("conversation_id",""))' <<<"$CHAT")
MESSAGE_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("message_id",""))' <<<"$CHAT")
[[ -n "$CONVERSATION_ID" ]] || die "Client chat response did not include conversation_id"
[[ -n "$MESSAGE_ID" ]] || die "Client chat response did not include message_id"

info "Listing conversations"
CONVERSATIONS=$(run_client conversations)
python3 - "$CONVERSATION_ID" <<'PY' <<<"$CONVERSATIONS"
import json, sys
conversation_id = sys.argv[1]
data = json.load(sys.stdin)
items = data.get("conversations", [])
assert any(item.get("conversation_id") == conversation_id for item in items), data
PY

info "Fetching message history for $CONVERSATION_ID"
MESSAGES=$(run_client messages --conversation-id "$CONVERSATION_ID")
python3 - "$MESSAGE_ID" <<'PY' <<<"$MESSAGES"
import json, sys
message_id = sys.argv[1]
data = json.load(sys.stdin)
items = data.get("messages", [])
assert any(item.get("message_id") == message_id for item in items), data
PY

info "Fetching events for $CONVERSATION_ID"
EVENTS=$(run_client events --conversation-id "$CONVERSATION_ID")
python3 -c 'import json,sys; data=json.load(sys.stdin); assert isinstance(data.get("events", []), list), data' <<<"$EVENTS" >/dev/null

if (( PRETTY )); then
  printf 'Health:\n%s\n\n' "$HEALTH"
  printf 'Chat:\n%s\n\n' "$CHAT"
  printf 'Conversations:\n%s\n\n' "$CONVERSATIONS"
  printf 'Messages:\n%s\n\n' "$MESSAGES"
  printf 'Events:\n%s\n' "$EVENTS"
else
  printf 'conversation_id=%s\nmessage_id=%s\n' "$CONVERSATION_ID" "$MESSAGE_ID"
fi

info "Client smoke test completed"
