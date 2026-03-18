#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

SESSION_STUB="$TMP_DIR/session-stub.sh"
cat > "$SESSION_STUB" <<'EOF_SESSION'
#!/usr/bin/env bash
set -euo pipefail
cmd=""
for arg in "$@"; do
  case "$arg" in
    chat|show|reset)
      cmd="$arg"
      break
      ;;
  esac
done
if [[ "$cmd" == chat ]]; then
  cat <<'EOF_JSON'
{"response":"# Hello\n\nStructured bridge test.","conversation_id":"conv_123","message_id":"msg_456","events":[{"tool":"browser","status":"ok","summary":"Fetched page title"}]}
EOF_JSON
  exit 0
fi
if [[ "$cmd" == show ]]; then
  echo '{"conversation_id":"conv_123"}'
  exit 0
fi
if [[ "$cmd" == reset ]]; then
  exit 0
fi
printf 'unexpected session command: %s\n' "$*" >&2
exit 1
EOF_SESSION
chmod +x "$SESSION_STUB"

CLIENT_STUB="$TMP_DIR/client-stub.sh"
cat > "$CLIENT_STUB" <<'EOF_CLIENT'
#!/usr/bin/env bash
set -euo pipefail
cmd=""
conv=""
for ((i=1;i<=$#;i++)); do
  arg="${!i}"
  case "$arg" in
    events|chat|health|conversations|messages)
      cmd="$arg"
      ;;
    --conversation-id)
      j=$((i+1))
      conv="${!j}"
      ;;
  esac
done
if [[ "$cmd" == "events" ]]; then
  cat <<'EOF_JSON'
{"conversation_id":"conv_123","events":[{"event_id":"evt_1","type":"tool_call","name":"browser.open","status":"completed","summary":"Opened page"},{"event_id":"evt_2","type":"tool_result","name":"browser.open","status":"completed","summary":"Got 200"}]}
EOF_JSON
  exit 0
fi
printf 'unexpected client command: %s\n' "$*" >&2
exit 1
EOF_CLIENT
chmod +x "$CLIENT_STUB"

out=$(STAVROBOT_SESSION_BIN="$SESSION_STUB" STAVROBOT_CLIENT_BIN="$CLIENT_STUB" "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out" '"ok": true'
assert_contains "$out" '"response": "# Hello\n\nStructured bridge test."'
assert_contains "$out" '"conversation_id": "conv_123"'
assert_contains "$out" '"message_id": "msg_456"'
assert_contains "$out" '"content": ['
assert_contains "$out" '"kind": "markdown"'
assert_contains "$out" '"display": {'
assert_contains "$out" '"tool_summary": ['
assert_contains "$out" '"tool": "browser"'
assert_contains "$out" '"raw": {'

extract_response=$(STAVROBOT_SESSION_BIN="$SESSION_STUB" "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi" --extract response)
assert_contains "$extract_response" '# Hello'

extract_conv=$(STAVROBOT_SESSION_BIN="$SESSION_STUB" "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi" --extract conversation_id)
assert_contains "$extract_conv" 'conv_123'

printf 'shelley-stavrobot-bridge structured-output tests passed\n'

SESSION_STUB_TEXT_ONLY="$TMP_DIR/session-stub-text-only.sh"
cat > "$SESSION_STUB_TEXT_ONLY" <<'EOF_SESSION2'
#!/usr/bin/env bash
set -euo pipefail
cmd=""
for arg in "$@"; do
  case "$arg" in
    chat|show|reset)
      cmd="$arg"
      break
      ;;
  esac
done
if [[ "$cmd" == chat ]]; then
  cat <<'EOF_JSON'
{"response":"events enrichment test","conversation_id":"conv_events","message_id":"msg_events"}
EOF_JSON
  exit 0
fi
if [[ "$cmd" == show ]]; then
  echo '{"conversation_id":"conv_events"}'
  exit 0
fi
if [[ "$cmd" == reset ]]; then
  exit 0
fi
printf 'unexpected session command: %s\n' "$*" >&2
exit 1
EOF_SESSION2
chmod +x "$SESSION_STUB_TEXT_ONLY"

CLIENT_STUB_EVENTS="$TMP_DIR/client-stub-events.sh"
cat > "$CLIENT_STUB_EVENTS" <<'EOF_CLIENT2'
#!/usr/bin/env bash
set -euo pipefail
cmd=""
for arg in "$@"; do
  case "$arg" in
    events|chat|health|conversations|messages)
      cmd="$arg"
      ;;
  esac
done
if [[ "$cmd" == "events" ]]; then
  cat <<'EOF_JSON'
{"conversation_id":"conv_events","events":[{"event_id":"evt_a","type":"tool_call","name":"execute_sql","status":"completed","summary":"Called execute_sql(...)"},{"event_id":"evt_b","type":"tool_result","name":"execute_sql","status":"completed","summary":"Result from execute_sql: ok"}]}
EOF_JSON
  exit 0
fi
printf 'unexpected client command: %s\n' "$*" >&2
exit 1
EOF_CLIENT2
chmod +x "$CLIENT_STUB_EVENTS"

out_events=$(STAVROBOT_SESSION_BIN="$SESSION_STUB_TEXT_ONLY" STAVROBOT_CLIENT_BIN="$CLIENT_STUB_EVENTS" "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_events" '"response": "events enrichment test"'
assert_contains "$out_events" '"display": {'
assert_contains "$out_events" '"tool_summary": ['
assert_contains "$out_events" '"tool": "execute_sql"'

SESSION_STUB_MEDIA="$TMP_DIR/session-stub-media.sh"
cat > "$SESSION_STUB_MEDIA" <<'EOF_SESSION3'
#!/usr/bin/env bash
set -euo pipefail
cmd=""
for arg in "$@"; do
  case "$arg" in
    chat|show|reset)
      cmd="$arg"
      break
      ;;
  esac
done
if [[ "$cmd" == chat ]]; then
  cat <<'EOF_JSON'
{"response":"See screenshot: https://cdn.example.test/capture.png","conversation_id":"conv_media","message_id":"msg_media"}
EOF_JSON
  exit 0
fi
if [[ "$cmd" == show ]]; then
  echo '{"conversation_id":"conv_media"}'
  exit 0
fi
if [[ "$cmd" == reset ]]; then
  exit 0
fi
printf 'unexpected session command: %s\n' "$*" >&2
exit 1
EOF_SESSION3
chmod +x "$SESSION_STUB_MEDIA"

CLIENT_STUB_MEDIA="$TMP_DIR/client-stub-media.sh"
cat > "$CLIENT_STUB_MEDIA" <<'EOF_CLIENT3'
#!/usr/bin/env bash
set -euo pipefail
cmd=""
for arg in "$@"; do
  case "$arg" in
    events|chat|health|conversations|messages)
      cmd="$arg"
      ;;
  esac
done
if [[ "$cmd" == "events" ]]; then
  cat <<'EOF_JSON'
{"conversation_id":"conv_media","events":[{"event_id":"evt_m1","type":"tool_result","name":"browser.screenshot","status":"completed","summary":"Saved screenshot https://cdn.example.test/capture.png"}]}
EOF_JSON
  exit 0
fi
printf 'unexpected client command: %s\n' "$*" >&2
exit 1
EOF_CLIENT3
chmod +x "$CLIENT_STUB_MEDIA"

out_media=$(STAVROBOT_SESSION_BIN="$SESSION_STUB_MEDIA" STAVROBOT_CLIENT_BIN="$CLIENT_STUB_MEDIA" "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_media" '"artifacts": ['
assert_contains "$out_media" '"kind": "image"'
assert_contains "$out_media" '"url": "https://cdn.example.test/capture.png"'
