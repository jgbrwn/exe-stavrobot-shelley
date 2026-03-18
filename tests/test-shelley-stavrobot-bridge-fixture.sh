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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to NOT contain: %s\n' "$needle" >&2
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
{"response":"fixture bridge test ok","conversation_id":"conv_fixture","message_id":"msg_fixture"}
EOF_JSON
  exit 0
fi
if [[ "$cmd" == show ]]; then
  echo '{"conversation_id":"conv_fixture"}'
  exit 0
fi
if [[ "$cmd" == reset ]]; then
  exit 0
fi
printf 'unexpected session command: %s\n' "$*" >&2
exit 1
EOF_SESSION
chmod +x "$SESSION_STUB"

out_plain=$(STAVROBOT_SESSION_BIN="$SESSION_STUB" "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_plain" '"response": "fixture bridge test ok"'
assert_not_contains "$out_plain" '"display": {'

out_fixture=$(STAVROBOT_SESSION_BIN="$SESSION_STUB" STAVROBOT_BRIDGE_FIXTURE=tool_summary "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_fixture" '"display": {'
assert_contains "$out_fixture" '"tool_summary": ['
assert_contains "$out_fixture" '"tool": "fixture.tool_summary"'
assert_contains "$out_fixture" '"title": "fixture generated tool summary for managed smoke validation"'

printf 'shelley-stavrobot-bridge fixture tests passed\n'
