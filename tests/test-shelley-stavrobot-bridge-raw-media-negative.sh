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

# Case 1: unsupported mime should be ignored and reported in media_notes.
SESSION_STUB_BAD_MIME="$TMP_DIR/session-stub-bad-mime.sh"
cat > "$SESSION_STUB_BAD_MIME" <<'EOF_BAD_MIME'
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
{"response":"bad mime","conversation_id":"conv_bad_mime","message_id":"msg_bad_mime","artifacts":[{"kind":"image","mime_type":"text/plain","data_base64":"aGVsbG8="}]}
EOF_JSON
  exit 0
fi
if [[ "$cmd" == show ]]; then
  echo '{"conversation_id":"conv_bad_mime"}'
  exit 0
fi
if [[ "$cmd" == reset ]]; then
  exit 0
fi
printf 'unexpected session command: %s\n' "$*" >&2
exit 1
EOF_BAD_MIME
chmod +x "$SESSION_STUB_BAD_MIME"

out_bad_mime=$(STAVROBOT_SESSION_BIN="$SESSION_STUB_BAD_MIME" "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_bad_mime" '"display": {'
assert_contains "$out_bad_mime" '"media_notes": ['
assert_contains "$out_bad_mime" 'unsupported mime text/plain'
assert_not_contains "$out_bad_mime" '"transport": "raw_inline_base64"'

# Case 2: invalid base64 should be ignored and reported in media_notes.
SESSION_STUB_BAD_B64="$TMP_DIR/session-stub-bad-b64.sh"
cat > "$SESSION_STUB_BAD_B64" <<'EOF_BAD_B64'
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
{"response":"bad b64","conversation_id":"conv_bad_b64","message_id":"msg_bad_b64","artifacts":[{"kind":"image","mime_type":"image/png","data_base64":"%%%not-base64%%%"}]}
EOF_JSON
  exit 0
fi
if [[ "$cmd" == show ]]; then
  echo '{"conversation_id":"conv_bad_b64"}'
  exit 0
fi
if [[ "$cmd" == reset ]]; then
  exit 0
fi
printf 'unexpected session command: %s\n' "$*" >&2
exit 1
EOF_BAD_B64
chmod +x "$SESSION_STUB_BAD_B64"

out_bad_b64=$(STAVROBOT_SESSION_BIN="$SESSION_STUB_BAD_B64" "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_bad_b64" '"display": {'
assert_contains "$out_bad_b64" '"media_notes": ['
assert_contains "$out_bad_b64" 'ignored raw media (artifacts): invalid-base64'
assert_not_contains "$out_bad_b64" '"transport": "raw_inline_base64"'

# Case 3: oversized raw media should be ignored and reported in media_notes.
big_b64=$(python3 - <<'PY'
import base64
print(base64.b64encode(b'a' * 64).decode())
PY
)

SESSION_STUB_TOO_LARGE="$TMP_DIR/session-stub-too-large.sh"
cat > "$SESSION_STUB_TOO_LARGE" <<EOF_TOO_LARGE
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
{"response":"too large","conversation_id":"conv_too_large","message_id":"msg_too_large","artifacts":[{"kind":"image","mime_type":"image/png","data_base64":"$big_b64"}]}
EOF_JSON
  exit 0
fi
if [[ "\$cmd" == show ]]; then
  echo '{"conversation_id":"conv_too_large"}'
  exit 0
fi
if [[ "\$cmd" == reset ]]; then
  exit 0
fi
printf 'unexpected session command: %s\n' "\$*" >&2
exit 1
EOF_TOO_LARGE
chmod +x "$SESSION_STUB_TOO_LARGE"

out_too_large=$(STAVROBOT_SESSION_BIN="$SESSION_STUB_TOO_LARGE" STAVROBOT_BRIDGE_RAW_MEDIA_MAX_BYTES=16 "$ROOT_DIR/shelley-stavrobot-bridge.sh" --message "hi")
assert_contains "$out_too_large" '"display": {'
assert_contains "$out_too_large" '"media_notes": ['
assert_contains "$out_too_large" 'too-large (64 > 16)'
assert_not_contains "$out_too_large" '"transport": "raw_inline_base64"'

printf 'shelley-stavrobot-bridge raw-media negative-case tests passed\n'
