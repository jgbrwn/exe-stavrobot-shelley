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

out_raw_fixture=$(STAVROBOT_SESSION_BIN="$SESSION_STUB" STAVROBOT_BRIDGE_FIXTURE=raw_media_image "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_raw_fixture" '"artifacts": ['
assert_contains "$out_raw_fixture" '"transport": "raw_inline_base64"'
assert_contains "$out_raw_fixture" '"title": "fixture raw media image for managed smoke validation"'

out_runtime_raw_only=$(STAVROBOT_SESSION_BIN="$SESSION_STUB" STAVROBOT_BRIDGE_FIXTURE=runtime_raw_media_only "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_runtime_raw_only" '"content": []'
assert_contains "$out_runtime_raw_only" '"transport": "raw_inline_base64"'
assert_contains "$out_runtime_raw_only" '"title": "fixture runtime raw-media only artifact"'

out_runtime_invalid=$(STAVROBOT_SESSION_BIN="$SESSION_STUB" STAVROBOT_BRIDGE_FIXTURE=runtime_invalid_raw_media "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_runtime_invalid" '"content": []'
assert_contains "$out_runtime_invalid" '"data_base64": "%%%not-base64%%%"'
assert_contains "$out_runtime_invalid" '"title": "fixture runtime invalid raw-media artifact"'

out_s2_fixture=$(STAVROBOT_SESSION_BIN="$SESSION_STUB" STAVROBOT_BRIDGE_FIXTURE=s2_markdown_tool_summary "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_s2_fixture" '"content": ['
assert_contains "$out_s2_fixture" '"kind": "markdown"'
assert_contains "$out_s2_fixture" '"text": "## S2 fixture heading' 
assert_contains "$out_s2_fixture" 'S2 markdown + tool-summary fixture body."'
assert_contains "$out_s2_fixture" '"display": {'
assert_contains "$out_s2_fixture" '"tool_summary": ['

out_s2_media_refs=$(STAVROBOT_SESSION_BIN="$SESSION_STUB" STAVROBOT_BRIDGE_FIXTURE=s2_markdown_media_refs "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_s2_media_refs" 'S2 markdown + media-ref fixture body.'
assert_contains "$out_s2_media_refs" '"kind": "image_ref"'
assert_contains "$out_s2_media_refs" '"url": "https://example.test/s2-content-image.png"'
assert_contains "$out_s2_media_refs" '"kind": "image"'
assert_contains "$out_s2_media_refs" '"url": "https://example.test/s2-artifact-image.png"'

out_s2_raw_fallback=$(STAVROBOT_SESSION_BIN="$SESSION_STUB" STAVROBOT_BRIDGE_FIXTURE=s2_markdown_raw_tool_events "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_s2_raw_fallback" '"content": ['
assert_contains "$out_s2_raw_fallback" 'S2 markdown + raw-event fallback fixture body.'
assert_contains "$out_s2_raw_fallback" '"raw": {'
assert_contains "$out_s2_raw_fallback" '"events": ['
assert_not_contains "$out_s2_raw_fallback" '"tool_summary": ['

printf 'shelley-stavrobot-bridge fixture tests passed\n'
