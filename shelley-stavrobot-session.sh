#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

STAVROBOT_DIR=""
CONFIG_PATH=""
BASE_URL="${STAVROBOT_BASE_URL:-http://localhost:8000}"
PASSWORD=""
MESSAGE=""
SOURCE=""
SENDER=""
CONNECT_TIMEOUT=10
REQUEST_TIMEOUT=300
RETRIES=1
RETRY_DELAY=2
PRETTY=0
EXTRACT=""
STATE_FILE="$ROOT_DIR/state/last-stavrobot-client-session.json"
COMMAND=""
CONVERSATION_ID=""

usage() {
  cat <<'EOF'
Usage: ./shelley-stavrobot-session.sh <command> [flags]

Commands:
  chat                      Send a chat turn using saved conversation state if present
  continue                  Alias for chat using saved conversation state
  chat                      Send a chat turn using saved conversation state if present
  continue                  Alias for chat using saved conversation state
  show                      Print saved local session state
  messages                  Fetch messages for saved conversation state
  events                    Fetch events for saved conversation state
  reset                     Remove saved local session state
  set --conversation-id ID  Save a conversation ID explicitly
  get FIELD                 Print one field from saved local session state

Flags:
  --stavrobot-dir PATH   Read password from PATH/data/main/config.toml
  --config-path PATH     Read password from config.toml
  --base-url URL         Stavrobot base URL (default: STAVROBOT_BASE_URL or http://localhost:8000)
  --password VALUE       Override password directly
  --message TEXT         Message to send for chat/continue; if omitted, read stdin
  --conversation-id ID   Explicit conversation ID override or value for set
  --source NAME          Optional source field for client chat
  --sender NAME          Optional sender field for client chat
  --state-file PATH      Override state file path
  --connect-timeout SEC  Curl connect timeout in seconds (default: 10)
  --request-timeout SEC  Total request timeout in seconds (default: 300)
  --retries COUNT        Retry count on transport failure (default: 1)
  --retry-delay SEC      Sleep between retries (default: 2)
  --pretty               Pretty-print JSON output
  --extract FIELD        For chat/messages/events/show output, print one field only
  --help

Session get/show extract fields:
  conversation_id
  message_id
  base_url
  source
  sender

Chat extract fields:
  response
  conversation_id
  message_id
EOF
}

read_message_if_needed() {
  [[ "$COMMAND" == "chat" || "$COMMAND" == "continue" ]] || return 0
  if [[ -n "$MESSAGE" ]]; then
    return 0
  fi
  if [[ -t 0 ]]; then
    die "Provide --message or pipe message text on stdin"
  fi
  MESSAGE=$(cat)
}

ensure_state_parent() {
  mkdir -p "$(dirname "$STATE_FILE")"
}

load_saved_conversation_id() {
  [[ -f "$STATE_FILE" ]] || return 0
  python3 - "$STATE_FILE" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    print(data.get('conversation_id', ''))
except Exception:
    print('')
PY
}

save_state_from_response() {
  local response_json="$1"
  ensure_state_parent
  python3 - "$STATE_FILE" "$BASE_URL" "$SOURCE" "$SENDER" "$response_json" <<'PY'
import json, sys
state_path, base_url, source, sender, response_json = sys.argv[1:6]
response = json.loads(response_json)
out = {
    'conversation_id': response.get('conversation_id', ''),
    'message_id': response.get('message_id', ''),
    'base_url': base_url,
    'source': source,
    'sender': sender,
}
with open(state_path, 'w') as f:
    json.dump(out, f, indent=2, sort_keys=True)
    f.write('\n')
PY
}

save_explicit_state() {
  ensure_state_parent
  python3 - "$STATE_FILE" "$CONVERSATION_ID" "$BASE_URL" <<'PY'
import json, sys
state_path, conversation_id, base_url = sys.argv[1:4]
out = {
    'conversation_id': conversation_id,
    'message_id': '',
    'base_url': base_url,
}
with open(state_path, 'w') as f:
    json.dump(out, f, indent=2, sort_keys=True)
    f.write('\n')
PY
}

print_state_field() {
  local field="$1"
  [[ -f "$STATE_FILE" ]] || die "No saved session state at $STATE_FILE"
  python3 - "$STATE_FILE" "$field" <<'PY'
import json, sys
state_path, field = sys.argv[1:3]
try:
    data = json.load(open(state_path))
except Exception:
    data = {}
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
}

run_client() {
  local -a cmd
  cmd=(
    "$ROOT_DIR/client-stavrobot.sh"
    --base-url "$BASE_URL"
    --connect-timeout "$CONNECT_TIMEOUT"
    --request-timeout "$REQUEST_TIMEOUT"
    --retries "$RETRIES"
    --retry-delay "$RETRY_DELAY"
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

extract_json_field() {
  local field="$1"
  local response_json="$2"
  python3 - "$field" "$response_json" <<'PY'
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
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    chat|continue|show|messages|events|reset|set|get)
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
    --state-file)
      STATE_FILE="$2"
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

[[ -n "$COMMAND" ]] || {
  usage >&2
  die "Missing command"
}
[[ "$CONNECT_TIMEOUT" =~ ^[0-9]+$ ]] || die "--connect-timeout must be an integer"
[[ "$REQUEST_TIMEOUT" =~ ^[0-9]+$ ]] || die "--request-timeout must be an integer"
[[ "$RETRIES" =~ ^[0-9]+$ ]] || die "--retries must be an integer"
[[ "$RETRY_DELAY" =~ ^[0-9]+$ ]] || die "--retry-delay must be an integer"
(( RETRIES >= 1 )) || die "--retries must be at least 1"
if (( PRETTY )) && [[ -n "$EXTRACT" ]]; then
  die "--pretty and --extract cannot be combined"
fi
read_message_if_needed

case "$COMMAND" in
  chat|continue)
    if [[ -z "$CONVERSATION_ID" ]]; then
      CONVERSATION_ID=$(load_saved_conversation_id)
    fi
    args=(chat --message "$MESSAGE")
    if [[ -n "$CONVERSATION_ID" ]]; then
      args+=(--conversation-id "$CONVERSATION_ID")
    fi
    if [[ -n "$SOURCE" ]]; then
      args+=(--source "$SOURCE")
    fi
    if [[ -n "$SENDER" ]]; then
      args+=(--sender "$SENDER")
    fi
    RAW_RESPONSE=$(run_client "${args[@]}")
    save_state_from_response "$RAW_RESPONSE"
    if [[ -n "$EXTRACT" ]]; then
      extract_json_field "$EXTRACT" "$RAW_RESPONSE"
    elif (( PRETTY )); then
      python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), indent=2, sort_keys=True))' <<<"$RAW_RESPONSE"
    else
      printf '%s\n' "$RAW_RESPONSE"
    fi
    ;;
  show)
    [[ -f "$STATE_FILE" ]] || die "No saved session state at $STATE_FILE"
    if [[ -n "$EXTRACT" ]]; then
      print_state_field "$EXTRACT"
    else
      cat "$STATE_FILE"
    fi
    ;;
  messages)
    if [[ -z "$CONVERSATION_ID" ]]; then
      CONVERSATION_ID=$(load_saved_conversation_id)
    fi
    [[ -n "$CONVERSATION_ID" ]] || die "No saved conversation_id; run chat first or use set"
    run_client messages --conversation-id "$CONVERSATION_ID"
    ;;
  events)
    if [[ -z "$CONVERSATION_ID" ]]; then
      CONVERSATION_ID=$(load_saved_conversation_id)
    fi
    [[ -n "$CONVERSATION_ID" ]] || die "No saved conversation_id; run chat first or use set"
    run_client events --conversation-id "$CONVERSATION_ID"
    ;;
  reset)
    rm -f "$STATE_FILE"
    info "Removed $STATE_FILE"
    ;;
  set)
    [[ -n "$CONVERSATION_ID" ]] || die "--conversation-id is required for set"
    save_explicit_state
    info "Saved conversation_id $CONVERSATION_ID to $STATE_FILE"
    ;;
  get)
    [[ -n "$EXTRACT" ]] || die "get requires --extract FIELD"
    print_state_field "$EXTRACT"
    ;;
esac
