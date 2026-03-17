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
  - use --extract response for human-oriented text-only output
  --pretty                Pretty-print JSON output
  --connect-timeout SEC   Curl connect timeout in seconds
  --request-timeout SEC   Total request timeout in seconds
  --retries COUNT         Retry count on transport failure
  --retry-delay SEC       Sleep between retries
  --help
EOF
}

run_session() {
  local -a cmd
  cmd=(
    "$ROOT_DIR/shelley-stavrobot-session.sh"
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

case "$COMMAND" in
  chat)
    if (( STATEFUL )); then
      if [[ -n "$MESSAGE" ]]; then
        run_session chat --message "$MESSAGE"
      else
        run_session chat
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
      run_client "${args[@]}"
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
