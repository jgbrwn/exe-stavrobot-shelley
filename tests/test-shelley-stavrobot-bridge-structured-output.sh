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

out=$(STAVROBOT_SESSION_BIN="$SESSION_STUB" "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
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
