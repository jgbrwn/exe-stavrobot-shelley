#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

STAVROBOT_DIR=""
CONFIG_PATH=""
BASE_URL="${STAVROBOT_BASE_URL:-http://localhost:8000}"
PASSWORD=""
MESSAGE=""
SOURCE="shelley"
SENDER="shelley"
STATE_FILE="$ROOT_DIR/state/last-stavrobot-client-session.json"
STATEFUL=1
COMMAND="chat"
EXTRACT=""
PRETTY=0
CONNECT_TIMEOUT=10
REQUEST_TIMEOUT=300
RETRIES=1
RETRY_DELAY=2
CONVERSATION_ID=""
STAVROBOT_SESSION_BIN="${STAVROBOT_SESSION_BIN:-$ROOT_DIR/shelley-stavrobot-session.sh}"
STAVROBOT_CLIENT_BIN="${STAVROBOT_CLIENT_BIN:-$ROOT_DIR/client-stavrobot.sh}"
STAVROBOT_BRIDGE_FIXTURE="${STAVROBOT_BRIDGE_FIXTURE:-}"

usage() {
  cat <<'EOF'
Usage: ./shelley-stavrobot-bridge.sh [flags]

Default behavior:
  - canonical Shelley-facing bridge
  - defaults to stateful chat with saved conversation reuse
  - defaults to printing full JSON bridge output for Shelley/runtime callers

Commands:
  chat            Send a chat turn (default)
  show-session    Show saved local session state
  reset-session   Remove saved local session state
  messages        Fetch messages for current/specified conversation
  events          Fetch events for current/specified conversation

Flags:
  --stateful              Use saved conversation state (default)
  --stateless             Do not use saved conversation state
  --stavrobot-dir PATH    Read password from PATH/data/main/config.toml
  --config-path PATH      Read password from config.toml
  --base-url URL          Stavrobot base URL
  --password VALUE        Override password directly
  --message TEXT          Message to send; if omitted, read stdin for chat
  --conversation-id ID    Explicit conversation ID override
  --source NAME           Source field (default: shelley)
  --sender NAME           Sender field (default: shelley)
  --state-file PATH       Override local session state path
  --extract FIELD         response|conversation_id|message_id|ok|base_url|source|sender

Notes:
  - default output is full JSON so Shelley/runtime callers can parse response text plus IDs
  - chat output now also includes narrow S2-ready fields like content/display/raw while preserving response/conversation_id/message_id
  - use --extract response for human-oriented text-only output
  - bridge now also attempts to enrich compact tool_summary from the events endpoint when chat payload lacks direct event/display fields
  - when STAVROBOT_BRIDGE_FIXTURE=tool_summary is set, chat output injects deterministic display.tool_summary only if no real summary is available (test/validation aid)
  --pretty                Pretty-print JSON output
  --connect-timeout SEC   Curl connect timeout in seconds
  --request-timeout SEC   Total request timeout in seconds
  --retries COUNT         Retry count on transport failure
  --retry-delay SEC       Sleep between retries
  --help

Environment:
  STAVROBOT_SESSION_BIN   Override session helper used by the bridge
  STAVROBOT_CLIENT_BIN    Override client helper used by the bridge
  STAVROBOT_BRIDGE_FIXTURE  Optional test fixture payload mode (e.g. tool_summary)
EOF
}

run_session() {
  local -a cmd
  cmd=(
    "$STAVROBOT_SESSION_BIN"
    --base-url "$BASE_URL"
    --state-file "$STATE_FILE"
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
  if [[ -n "$CONVERSATION_ID" ]]; then
    cmd+=(--conversation-id "$CONVERSATION_ID")
  fi
  if [[ -n "$SOURCE" ]]; then
    cmd+=(--source "$SOURCE")
  fi
  if [[ -n "$SENDER" ]]; then
    cmd+=(--sender "$SENDER")
  fi
  if (( PRETTY )); then
    cmd+=(--pretty)
  fi
  if [[ -n "$EXTRACT" ]]; then
    cmd+=(--extract "$EXTRACT")
  fi
  "${cmd[@]}" "$@"
}

run_client() {
  local -a cmd
  cmd=(
    "$STAVROBOT_CLIENT_BIN"
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
  if [[ -n "$EXTRACT" ]]; then
    cmd+=(--extract "$EXTRACT")
  fi
  if (( PRETTY )); then
    cmd+=(--pretty)
  fi
  "${cmd[@]}" "$@"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    chat|show-session|reset-session|messages|events)
      COMMAND="$1"
      shift
      ;;
    --stateful)
      STATEFUL=1
      shift
      ;;
    --stateless)
      STATEFUL=0
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
    --extract)
      EXTRACT="$2"
      shift 2
      ;;
    --pretty)
      PRETTY=1
      EXTRACT=""
      shift
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
    --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ "$CONNECT_TIMEOUT" =~ ^[0-9]+$ ]] || die "--connect-timeout must be an integer"
[[ "$REQUEST_TIMEOUT" =~ ^[0-9]+$ ]] || die "--request-timeout must be an integer"
[[ "$RETRIES" =~ ^[0-9]+$ ]] || die "--retries must be an integer"
[[ "$RETRY_DELAY" =~ ^[0-9]+$ ]] || die "--retry-delay must be an integer"
(( RETRIES >= 1 )) || die "--retries must be at least 1"

render_bridge_chat_json() {
  local response_json="$1"
  local events_json="${2:-}"
  python3 - "$response_json" "$STAVROBOT_BRIDGE_FIXTURE" "$events_json" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
fixture = sys.argv[2]
events_json = sys.argv[3]
response = payload.get('response', '')
out = {
    'ok': True,
    'response': response,
    'conversation_id': payload.get('conversation_id', ''),
    'message_id': payload.get('message_id', ''),
    'content': [],
    'display': {},
    'raw': payload,
}
if response:
    out['content'].append({'kind': 'markdown', 'text': response})

tool_summary = []
seen = set()

def append_summary_item(item):
    if not isinstance(item, dict):
        return
    tool = str(item.get('tool') or item.get('name') or item.get('type') or 'tool')
    status = str(item.get('status') or item.get('result') or 'ok')
    title = str(item.get('title') or item.get('summary') or item.get('message') or '')
    if tool == 'tool' and not title:
        return
    key = (tool, status, title)
    if key in seen:
        return
    seen.add(key)
    tool_summary.append({'tool': tool, 'status': status, 'title': title})

# Prefer direct payload display summary when present.
display = payload.get('display')
if isinstance(display, dict):
    for item in (display.get('tool_summary') or []):
        append_summary_item(item)

# Then accept direct payload event-ish lists.
if not tool_summary:
    for key in ('events', 'tool_events', 'tool_summary'):
        value = payload.get(key)
        if isinstance(value, list) and value:
            for item in value:
                append_summary_item(item)
            if tool_summary:
                break

# If chat payload was text-only, enrich from events endpoint output when available.
if not tool_summary and events_json:
    try:
        event_payload = json.loads(events_json)
    except Exception:
        event_payload = None
    if isinstance(event_payload, dict):
        events = event_payload.get('events') or []
        if isinstance(events, list):
            for item in events[-8:]:
                if not isinstance(item, dict):
                    continue
                # Keep only tool-oriented event types for compact summary.
                event_type = str(item.get('type') or '')
                if event_type and not event_type.startswith('tool_'):
                    continue
                append_summary_item(item)

if fixture == 'tool_summary' and not tool_summary:
    tool_summary = [{
        'tool': 'fixture.tool_summary',
        'status': 'ok',
        'title': 'fixture generated tool summary for managed smoke validation',
    }]
if tool_summary:
    out['display']['tool_summary'] = tool_summary[:8]
if not out['display']:
    out.pop('display')
print(json.dumps(out, indent=2))
PY
}

fetch_chat_events_json() {
  local chat_json="$1"
  local conv_id
  conv_id=$(python3 - "$chat_json" <<'PY'
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    print("")
    raise SystemExit(0)
print(data.get('conversation_id') or "")
PY
)
  [[ -n "$conv_id" ]] || return 0

  local events_json
  if events_json=$(run_client events --conversation-id "$conv_id" 2>/dev/null); then
    printf '%s\n' "$events_json"
  fi
}

case "$COMMAND" in
  chat)
    if (( STATEFUL )); then
      if [[ -n "$MESSAGE" ]]; then
        chat_json=$(run_session chat --message "$MESSAGE")
      else
        chat_json=$(run_session chat)
      fi
    else
      args=(chat)
      if [[ -n "$MESSAGE" ]]; then
        args+=(--message "$MESSAGE")
      fi
      if [[ -n "$CONVERSATION_ID" ]]; then
        args+=(--conversation-id "$CONVERSATION_ID")
      fi
      if [[ -n "$SOURCE" ]]; then
        args+=(--source "$SOURCE")
      fi
      if [[ -n "$SENDER" ]]; then
        args+=(--sender "$SENDER")
      fi
      chat_json=$(run_client "${args[@]}")
    fi

    if [[ -n "$EXTRACT" ]]; then
      python3 - "$EXTRACT" "$chat_json" <<'PY'
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
    else
      events_json=""
      if [[ -z "$STAVROBOT_BRIDGE_FIXTURE" || "$STAVROBOT_BRIDGE_FIXTURE" == "tool_summary" ]]; then
        events_json=$(fetch_chat_events_json "$chat_json" || true)
      fi
      render_bridge_chat_json "$chat_json" "$events_json"
    fi
    ;;
  show-session)
    run_session show
    ;;
  reset-session)
    run_session reset
    ;;
  messages)
    if (( STATEFUL )); then
      run_session messages
    else
      [[ -n "$CONVERSATION_ID" ]] || die "--conversation-id is required with --stateless messages"
      run_client messages --conversation-id "$CONVERSATION_ID"
    fi
    ;;
  events)
    if (( STATEFUL )); then
      run_session events
    else
      [[ -n "$CONVERSATION_ID" ]] || die "--conversation-id is required with --stateless events"
      run_client events --conversation-id "$CONVERSATION_ID"
    fi
    ;;
esac
