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

SESSION_STUB_RAW_MEDIA="$TMP_DIR/session-stub-raw-media.sh"
cat > "$SESSION_STUB_RAW_MEDIA" <<'EOF_SESSION4'
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
{"response":"raw media reply","conversation_id":"conv_raw","message_id":"msg_raw","artifacts":[{"kind":"image","mime_type":"image/png","data_base64":"iVBORw0KGgo="}]}
EOF_JSON
  exit 0
fi
if [[ "$cmd" == show ]]; then
  echo '{"conversation_id":"conv_raw"}'
  exit 0
fi
if [[ "$cmd" == reset ]]; then
  exit 0
fi
printf 'unexpected session command: %s\n' "$*" >&2
exit 1
EOF_SESSION4
chmod +x "$SESSION_STUB_RAW_MEDIA"

out_raw=$(STAVROBOT_SESSION_BIN="$SESSION_STUB_RAW_MEDIA" "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_raw" '"artifacts": ['
assert_contains "$out_raw" '"transport": "raw_inline_base64"'
assert_contains "$out_raw" '"mime_type": "image/png"'
assert_contains "$out_raw" '"data_base64": "iVBORw0KGgo="'

big_b64=$(python3 - <<'PY'
import base64
print(base64.b64encode(b'a' * 64).decode())
PY
)

SESSION_STUB_RAW_MEDIA_TOO_LARGE="$TMP_DIR/session-stub-raw-media-too-large.sh"
cat > "$SESSION_STUB_RAW_MEDIA_TOO_LARGE" <<EOF_SESSION5
#!/usr/bin/env bash
set -euo pipefail
cmd=""
for arg in "\$@"; do
  case "\$arg" in
    chat|show|reset)
      cmd="\$arg"
      break
      ;;
  esac
done
if [[ "\$cmd" == chat ]]; then
  cat <<'EOF_JSON'
{"response":"oversize raw media","conversation_id":"conv_raw2","message_id":"msg_raw2","artifacts":[{"kind":"image","mime_type":"image/png","data_base64":"$big_b64"}]}
EOF_JSON
  exit 0
fi
if [[ "\$cmd" == show ]]; then
  echo '{"conversation_id":"conv_raw2"}'
  exit 0
fi
if [[ "\$cmd" == reset ]]; then
  exit 0
fi
printf 'unexpected session command: %s\n' "\$*" >&2
exit 1
EOF_SESSION5
chmod +x "$SESSION_STUB_RAW_MEDIA_TOO_LARGE"

out_raw_large=$(STAVROBOT_SESSION_BIN="$SESSION_STUB_RAW_MEDIA_TOO_LARGE" STAVROBOT_BRIDGE_RAW_MEDIA_MAX_BYTES=16 "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_raw_large" '"display": {'
assert_contains "$out_raw_large" '"media_notes": ['
assert_contains "$out_raw_large" 'too-large (64 > 16)'
if grep -Fq -- '"transport": "raw_inline_base64"' <<<"$out_raw_large"; then
  printf 'did not expect oversized raw media artifact to be preserved\n' >&2
  printf -- '--- output ---\n%s\n------------\n' "$out_raw_large" >&2
  exit 1
fi
