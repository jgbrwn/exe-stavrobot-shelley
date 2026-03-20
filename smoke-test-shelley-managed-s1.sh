#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

SHELLEY_DIR="${SHELLEY_DIR:-/opt/shelley}"
SHELLEY_BIN=""
PORT="8765"
DB_PATH="/tmp/shelley-stavrobot-managed-test.db"
BASE_URL=""
PROFILE_STATE_PATH="${PROFILE_STATE_PATH:-$ROOT_DIR/state/shelley-bridge-profiles.json}"
STAVROBOT_BASE_URL="${STAVROBOT_BASE_URL:-http://localhost:8000}"
STAVROBOT_CONFIG_PATH="${STAVROBOT_CONFIG_PATH:-/tmp/stavrobot/data/main/config.toml}"
BRIDGE_PROFILE="local-default"
NORMAL_EXPECTED="managed normal control ok"
STAVROBOT_EXPECTED="managed spike first turn ok"
STAVROBOT_SECOND_EXPECTED="managed spike second turn ok"
TMUX_SESSION="shelley-managed-s1-smoke"
KEEP_SERVER=0
EXPECT_DISPLAY_DATA=0
REQUIRE_DISPLAY_HINTS=0
EXPECT_MEDIA_REFS=0
REQUIRE_MEDIA_REFS=0
EXPECT_NATIVE_RAW_MEDIA_GATING=0
REQUIRE_NATIVE_RAW_MEDIA_HINTS=0
EXPECT_RAW_MEDIA_REJECTION=0
REQUIRE_RAW_MEDIA_REJECTION_HINTS=0
EXPECT_S2_MARKDOWN_TOOL_SUMMARY=0
REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS=0
EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK=0
REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS=0
BRIDGE_FIXTURE=""
SERVER_LOG="/tmp/shelley-managed-s1-smoke.log"

find_port_listener() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp "sport = :$PORT" 2>/dev/null | awk 'NR>1 {print}' || true
    return
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | tail -n +2 || true
    return
  fi
  printf ''
}

usage() {
  cat <<'EOF'
Usage: ./smoke-test-shelley-managed-s1.sh [flags]

Flags:
  --shelley-dir PATH             Shelley checkout/build dir (default: /opt/shelley or SHELLEY_DIR)
  --shelley-bin PATH             Shelley binary path (default: SHELLEY_DIR/bin/shelley)
  --port PORT                    Test port (default: 8765)
  --db-path PATH                 Test sqlite db path
  --profile-state-path PATH      Managed bridge profile state file (default: repo state/shelley-bridge-profiles.json)
  --stavrobot-base-url URL       Stavrobot base URL override for disposable/local validation
  --stavrobot-config-path PATH   Stavrobot config path override for disposable/local validation
  --bridge-profile NAME          Bridge profile name for Stavrobot conversation (default: local-default)
  --tmux-session NAME            tmux session name used for test server
  --keep-server                  Leave test Shelley server running after success
  --expect-display-data          Assert Stavrobot assistant messages persist display_data
  --require-display-hints        With --expect-display-data, fail if no display-hint payloads are observed
  --expect-media-refs            Assert persisted display_data.media_refs when artifact/image hints are present (URL and/or raw-inline hints)
  --require-media-refs           With --expect-media-refs, fail if no media-ref hints are observed
  --expect-native-raw-media-gating  Assert phase-2 native mapping gate: raw-inline media maps to native content only when no assistant text exists
  --require-native-raw-media-hints  With --expect-native-raw-media-gating, fail if no raw-inline hints are observed
  --expect-raw-media-rejection   Assert invalid raw-inline artifacts are rejected at runtime (no persisted raw media_ref + unsupported_kinds evidence)
  --require-raw-media-rejection-hints  With --expect-raw-media-rejection, fail if no invalid raw-inline hints are observed
  --expect-s2-markdown-tool-summary  Assert markdown-first content + display.tool_summary persistence behavior
  --require-s2-markdown-tool-summary-hints  With --expect-s2-markdown-tool-summary, fail if no markdown/tool_summary hints are observed
  --expect-s2-tool-summary-raw-fallback  Assert runtime derives display.tool_summary from raw.events when display.tool_summary is absent
  --require-s2-tool-summary-raw-fallback-hints  With --expect-s2-tool-summary-raw-fallback, fail if no raw.events hints are observed
  --bridge-fixture NAME          Optional bridge fixture mode for smoke server (e.g. tool_summary, runtime_raw_media_only, runtime_invalid_raw_media, s2_markdown_tool_summary, s2_markdown_raw_tool_events)
  --help

Notes:
  - assumes the Shelley build already contains a Stavrobot-capable S1 patch
  - starts an isolated Shelley server on a safe port with its own DB
  - validates both normal Shelley behavior and Stavrobot-mode behavior
  - expects a managed bridge-profile state file and a JSON-emitting Shelley bridge compatible with the current S1 runtime contract
EOF
}

json_field() {
  local json_file="$1"
  local path="$2"
  python3 - "$json_file" "$path" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
cur = data
for part in sys.argv[2].split('.'):
    if not part:
        continue
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print("")
        raise SystemExit(0)
if isinstance(cur, bool):
    print("true" if cur else "false")
elif cur is None:
    print("")
else:
    print(cur)
PY
}

post_json() {
  local path="$1"
  local payload="$2"
  curl -sS -X POST "$BASE_URL$path" -H 'Content-Type: application/json' -d "$payload"
}

get_json() {
  local path="$1"
  curl -sS "$BASE_URL$path"
}

assert_conversation_contains_text() {
  local json_file="$1"
  local needle="$2"
  python3 - "$json_file" "$needle" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
needle = sys.argv[2]
messages = data.get("messages", [])
texts = []
for msg in messages:
    for item in msg.get("content", []) or []:
        if isinstance(item, dict):
            text = item.get("Text") or item.get("text")
            if text:
                texts.append(text)
    raw = msg.get("llm_data")
    if raw:
        try:
            parsed = json.loads(raw) if isinstance(raw, str) else raw
        except Exception:
            parsed = None
        if isinstance(parsed, dict):
            for item in parsed.get("Content", []) or []:
                if isinstance(item, dict):
                    text = item.get("Text") or item.get("text")
                    if text:
                        texts.append(text)
joined = "\n".join(texts)
if needle not in joined:
    raise SystemExit(f"conversation did not include expected text: {needle}")
PY
}

cleanup() {
  if (( KEEP_SERVER == 0 )); then
    tmux kill-session -t "$TMUX_SESSION" >/dev/null 2>&1 || true
    local linger
    linger=$(find_port_listener)
    if [[ -n "$linger" ]]; then
      warn "Port $PORT still has a listener after smoke cleanup"
      warn "$linger"
    fi
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shelley-dir)
      SHELLEY_DIR="$2"
      shift 2
      ;;
    --shelley-bin)
      SHELLEY_BIN="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --db-path)
      DB_PATH="$2"
      shift 2
      ;;
    --profile-state-path)
      PROFILE_STATE_PATH="$2"
      shift 2
      ;;
    --stavrobot-base-url)
      STAVROBOT_BASE_URL="$2"
      shift 2
      ;;
    --stavrobot-config-path)
      STAVROBOT_CONFIG_PATH="$2"
      shift 2
      ;;
    --bridge-profile)
      BRIDGE_PROFILE="$2"
      shift 2
      ;;
    --tmux-session)
      TMUX_SESSION="$2"
      shift 2
      ;;
    --keep-server)
      KEEP_SERVER=1
      shift
      ;;
    --expect-display-data)
      EXPECT_DISPLAY_DATA=1
      shift
      ;;
    --require-display-hints)
      REQUIRE_DISPLAY_HINTS=1
      shift
      ;;
    --expect-media-refs)
      EXPECT_MEDIA_REFS=1
      shift
      ;;
    --require-media-refs)
      REQUIRE_MEDIA_REFS=1
      shift
      ;;
    --expect-native-raw-media-gating)
      EXPECT_NATIVE_RAW_MEDIA_GATING=1
      shift
      ;;
    --require-native-raw-media-hints)
      REQUIRE_NATIVE_RAW_MEDIA_HINTS=1
      shift
      ;;
    --expect-raw-media-rejection)
      EXPECT_RAW_MEDIA_REJECTION=1
      shift
      ;;
    --require-raw-media-rejection-hints)
      REQUIRE_RAW_MEDIA_REJECTION_HINTS=1
      shift
      ;;
    --expect-s2-markdown-tool-summary)
      EXPECT_S2_MARKDOWN_TOOL_SUMMARY=1
      shift
      ;;
    --require-s2-markdown-tool-summary-hints)
      REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS=1
      shift
      ;;
    --expect-s2-tool-summary-raw-fallback)
      EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK=1
      shift
      ;;
    --require-s2-tool-summary-raw-fallback-hints)
      REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS=1
      shift
      ;;
    --bridge-fixture)
      BRIDGE_FIXTURE="$2"
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

require_cmd tmux
require_cmd curl
require_cmd python3
require_cmd sqlite3

[[ -n "$SHELLEY_BIN" ]] || SHELLEY_BIN="$SHELLEY_DIR/bin/shelley"
[[ -x "$SHELLEY_BIN" ]] || die "Shelley binary not found or not executable: $SHELLEY_BIN"
[[ -f "$PROFILE_STATE_PATH" ]] || die "Managed bridge profile state file not found: $PROFILE_STATE_PATH"
[[ -f "$STAVROBOT_CONFIG_PATH" ]] || die "Stavrobot config path not found: $STAVROBOT_CONFIG_PATH"
[[ "$PORT" =~ ^[0-9]+$ ]] || die "--port must be numeric"
if (( REQUIRE_DISPLAY_HINTS == 1 && EXPECT_DISPLAY_DATA == 0 )); then
  die "--require-display-hints requires --expect-display-data"
fi
if (( REQUIRE_MEDIA_REFS == 1 && EXPECT_MEDIA_REFS == 0 )); then
  die "--require-media-refs requires --expect-media-refs"
fi
if (( REQUIRE_NATIVE_RAW_MEDIA_HINTS == 1 && EXPECT_NATIVE_RAW_MEDIA_GATING == 0 )); then
  die "--require-native-raw-media-hints requires --expect-native-raw-media-gating"
fi
if (( REQUIRE_RAW_MEDIA_REJECTION_HINTS == 1 && EXPECT_RAW_MEDIA_REJECTION == 0 )); then
  die "--require-raw-media-rejection-hints requires --expect-raw-media-rejection"
fi
if (( REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS == 1 && EXPECT_S2_MARKDOWN_TOOL_SUMMARY == 0 )); then
  die "--require-s2-markdown-tool-summary-hints requires --expect-s2-markdown-tool-summary"
fi
if (( REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS == 1 && EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK == 0 )); then
  die "--require-s2-tool-summary-raw-fallback-hints requires --expect-s2-tool-summary-raw-fallback"
fi

python3 "$ROOT_DIR/py/shelley_bridge_profiles.py" validate "$PROFILE_STATE_PATH" >/dev/null
python3 "$ROOT_DIR/py/shelley_bridge_profiles.py" resolve "$PROFILE_STATE_PATH" "$BRIDGE_PROFILE" >/dev/null

BASE_URL="http://localhost:$PORT"
rm -f "$DB_PATH" "$SERVER_LOG"
tmux kill-session -t "$TMUX_SESSION" >/dev/null 2>&1 || true

port_listener_before=$(find_port_listener)
if [[ -n "$port_listener_before" ]]; then
  printf '[error] Port %s is already in use before smoke start\n' "$PORT" >&2
  printf '[error] Listener details:\n%s\n' "$port_listener_before" >&2
  die "Choose a different --port/--tmux-session or stop the existing listener"
fi

server_env=""
if [[ -n "$BRIDGE_FIXTURE" ]]; then
  server_env="STAVROBOT_BRIDGE_FIXTURE='$BRIDGE_FIXTURE' "
fi

info "Starting isolated Shelley test server on port $PORT"
tmux new-session -d -s "$TMUX_SESSION" \
  "cd '$SHELLEY_DIR' && ${server_env}'$SHELLEY_BIN' -predictable-only -default-model predictable -model predictable -db '$DB_PATH' serve -port '$PORT' -socket none >'$SERVER_LOG' 2>&1"

info "Waiting for Shelley server readiness"
for _ in $(seq 1 30); do
  if curl -fsS "$BASE_URL/" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS "$BASE_URL/" >/dev/null 2>&1 || {
  tmux capture-pane -pt "$TMUX_SESSION" || true
  die "Shelley test server did not become ready"
}

info "Creating normal control conversation"
normal_payload=$(python3 - "$NORMAL_EXPECTED" <<'PY'
import json, sys
print(json.dumps({"message": f"Reply with exactly: {sys.argv[1]}"}))
PY
)
normal_tmp=$(mktemp)
post_json "/api/conversations/new" "$normal_payload" >"$normal_tmp"
normal_conversation_id=$(json_field "$normal_tmp" conversation_id)
[[ -n "$normal_conversation_id" ]] || die "Normal conversation create did not return conversation_id"

sleep 2
normal_conv_tmp=$(mktemp)
get_json "/api/conversation/$normal_conversation_id" >"$normal_conv_tmp"
assert_conversation_contains_text "$normal_conv_tmp" "$NORMAL_EXPECTED"

info "Creating Stavrobot-mode conversation"
stavrobot_payload=$(python3 - "$STAVROBOT_EXPECTED" "$BRIDGE_PROFILE" <<'PY'
import json, sys
print(json.dumps({
  "message": f"Reply with exactly: {sys.argv[1]}",
  "conversation_options": {
    "type": "stavrobot",
    "stavrobot": {
      "enabled": True,
      "bridge_profile": sys.argv[2],
    },
  },
}))
PY
)
stavrobot_tmp=$(mktemp)
post_json "/api/conversations/new" "$stavrobot_payload" >"$stavrobot_tmp"
stavrobot_conversation_id=$(json_field "$stavrobot_tmp" conversation_id)
[[ -n "$stavrobot_conversation_id" ]] || die "Stavrobot conversation create did not return conversation_id"

sleep 3
stavrobot_conv_tmp=$(mktemp)
get_json "/api/conversation/$stavrobot_conversation_id" >"$stavrobot_conv_tmp"
assert_conversation_contains_text "$stavrobot_conv_tmp" "$STAVROBOT_EXPECTED"

info "Sending Stavrobot continuation turn"
second_payload=$(python3 - "$STAVROBOT_SECOND_EXPECTED" <<'PY'
import json, sys
print(json.dumps({"message": f"Reply with exactly: {sys.argv[1]}"}))
PY
)
second_tmp=$(mktemp)
post_json "/api/conversation/$stavrobot_conversation_id/chat" "$second_payload" >"$second_tmp"
sleep 3

stavrobot_conv_tmp2=$(mktemp)
get_json "/api/conversation/$stavrobot_conversation_id" >"$stavrobot_conv_tmp2"
assert_conversation_contains_text "$stavrobot_conv_tmp2" "$STAVROBOT_SECOND_EXPECTED"

info "Checking persisted conversation metadata"
sqlite_tmp=$(mktemp)
sqlite3 "$DB_PATH" "SELECT conversation_options FROM conversations WHERE conversation_id='$stavrobot_conversation_id';" >"$sqlite_tmp"
python3 - "$sqlite_tmp" "$BRIDGE_PROFILE" <<'PY'
import json, sys
raw = open(sys.argv[1]).read().strip()
if not raw:
    raise SystemExit("no conversation_options persisted for stavrobot conversation")
data = json.loads(raw)
if data.get("type") != "stavrobot":
    raise SystemExit("conversation type is not stavrobot")
st = data.get("stavrobot") or {}
if not st.get("enabled"):
    raise SystemExit("stavrobot.enabled not true")
if st.get("bridge_profile") != sys.argv[2]:
    raise SystemExit("bridge_profile mismatch")
if not st.get("conversation_id"):
    raise SystemExit("remote stavrobot conversation_id missing")
if not st.get("last_message_id"):
    raise SystemExit("remote stavrobot last_message_id missing")
PY

if (( EXPECT_DISPLAY_DATA == 1 )); then
  info "Checking persisted display_data on Stavrobot assistant messages"
  sqlite_display_tmp=$(mktemp)
  sqlite3 -json "$DB_PATH" "SELECT sequence_id, user_data, display_data FROM messages WHERE conversation_id='$stavrobot_conversation_id' AND type='agent' ORDER BY sequence_id;" >"$sqlite_display_tmp"
  check_result=$(python3 - "$sqlite_display_tmp" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
requires_display = 0
missing = []
for row in rows:
    ud = row.get("user_data")
    if not ud:
        continue
    try:
        parsed = json.loads(ud)
    except Exception:
        continue
    st = (parsed.get("stavrobot") or {}) if isinstance(parsed, dict) else {}
    raw = st.get("raw_payload") if isinstance(st, dict) else None
    if not isinstance(raw, dict):
        continue
    has_tool_summary = isinstance(raw.get("display"), dict) and bool(raw.get("display", {}).get("tool_summary"))
    has_media_ref = any(isinstance(item, dict) and item.get("kind") == "image_ref" and item.get("url") for item in (raw.get("content") or []))
    has_artifact_media = any(isinstance(item, dict) and item.get("kind") == "image" and item.get("url") for item in (raw.get("artifacts") or []))
    if has_tool_summary or has_media_ref or has_artifact_media:
        requires_display += 1
        if not row.get("display_data"):
            missing.append(str(row.get("sequence_id")))

if requires_display == 0:
    print("not_required")
elif missing:
    raise SystemExit("display_data missing for agent sequence_ids: " + ",".join(missing))
else:
    print("required_ok")
PY
)
  if [[ "$check_result" == "not_required" ]]; then
    if (( REQUIRE_DISPLAY_HINTS == 1 )); then
      die "Expected display-hint payloads but none were observed in sampled Stavrobot turns"
    fi
    info "No display-hint payloads observed in smoke turn outputs; display_data assertion not required for this run"
  fi
fi

if (( EXPECT_MEDIA_REFS == 1 )); then
  info "Checking persisted display_data.media_refs on Stavrobot assistant messages"
  sqlite_media_tmp=$(mktemp)
  sqlite3 -json "$DB_PATH" "SELECT sequence_id, user_data, display_data FROM messages WHERE conversation_id='$stavrobot_conversation_id' AND type='agent' ORDER BY sequence_id;" >"$sqlite_media_tmp"
  media_result=$(python3 - "$sqlite_media_tmp" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
requires_media = 0
missing = []
for row in rows:
    ud = row.get("user_data")
    if not ud:
        continue
    try:
        parsed = json.loads(ud)
    except Exception:
        continue
    st = (parsed.get("stavrobot") or {}) if isinstance(parsed, dict) else {}
    raw = st.get("raw_payload") if isinstance(st, dict) else None
    if not isinstance(raw, dict):
        continue

    has_hint = False
    requires_raw_media = False
    for item in (raw.get("content") or []):
        if isinstance(item, dict) and item.get("kind") == "image_ref" and item.get("url"):
            has_hint = True
            break
    for item in (raw.get("artifacts") or []):
        if not isinstance(item, dict) or item.get("kind") != "image":
            continue
        if item.get("url"):
            has_hint = True
        if item.get("transport") == "raw_inline_base64" or item.get("data_base64"):
            has_hint = True
            requires_raw_media = True

    if has_hint:
        requires_media += 1
        display_raw = row.get("display_data")
        if not display_raw:
            missing.append(f"{row.get('sequence_id')}:display_data_missing")
            continue
        try:
            display = json.loads(display_raw)
        except Exception:
            missing.append(f"{row.get('sequence_id')}:display_data_invalid_json")
            continue
        media_refs = display.get("media_refs")
        if not isinstance(media_refs, list) or not media_refs:
            missing.append(f"{row.get('sequence_id')}:media_refs_missing")
            continue
        if requires_raw_media:
            raw_refs = [
                ref for ref in media_refs
                if isinstance(ref, dict)
                and (
                    ref.get("transport") == "raw_inline_base64"
                    or bool(ref.get("data_base64"))
                )
            ]
            if not raw_refs:
                missing.append(f"{row.get('sequence_id')}:raw_media_ref_missing")

if requires_media == 0:
    print("not_required")
elif missing:
    raise SystemExit("media_refs missing for agent sequence_ids: " + ",".join(missing))
else:
    print("required_ok")
PY
)
  if [[ "$media_result" == "not_required" ]]; then
    if (( REQUIRE_MEDIA_REFS == 1 )); then
      die "Expected media-ref hints but none were observed in sampled Stavrobot turns"
    fi
    info "No media-ref hints observed in smoke turn outputs; media_refs assertion not required for this run"
  fi
fi

if (( EXPECT_NATIVE_RAW_MEDIA_GATING == 1 )); then
  info "Checking runtime phase-2 native raw-media mapping gate"
  sqlite_gate_tmp=$(mktemp)
  sqlite3 -json "$DB_PATH" "SELECT sequence_id, llm_data, user_data, display_data FROM messages WHERE conversation_id='$stavrobot_conversation_id' AND type='agent' ORDER BY sequence_id;" >"$sqlite_gate_tmp"
  gate_result=$(python3 - "$sqlite_gate_tmp" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
hint_rows = 0
violations = []
for row in rows:
    ud = row.get("user_data")
    if not ud:
        continue
    try:
        parsed = json.loads(ud)
    except Exception:
        continue
    st = (parsed.get("stavrobot") or {}) if isinstance(parsed, dict) else {}
    raw = st.get("raw_payload") if isinstance(st, dict) else None
    if not isinstance(raw, dict):
        continue

    raw_artifacts = [
        item for item in (raw.get("artifacts") or [])
        if isinstance(item, dict)
        and item.get("kind") == "image"
        and (item.get("transport") == "raw_inline_base64" or item.get("data_base64"))
    ]
    if not raw_artifacts:
        continue
    hint_rows += 1

    has_text = any(
        isinstance(item, dict)
        and item.get("kind") in ("text", "markdown")
        and bool(item.get("text"))
        for item in (raw.get("content") or [])
    )

    llm_raw = row.get("llm_data")
    llm = {}
    if isinstance(llm_raw, str) and llm_raw:
        try:
            llm = json.loads(llm_raw)
        except Exception:
            llm = {}
    content = llm.get("Content") if isinstance(llm, dict) else []
    if not isinstance(content, list):
        content = []

    has_native_raw_media = any(
        isinstance(c, dict)
        and c.get("MediaType")
        and c.get("Data")
        for c in content
    )

    display_raw = row.get("display_data")
    display = {}
    if isinstance(display_raw, str) and display_raw:
        try:
            display = json.loads(display_raw)
        except Exception:
            display = {}
    media_refs = display.get("media_refs") if isinstance(display, dict) else None
    if not isinstance(media_refs, list):
        media_refs = []
    has_persisted_raw_ref = any(
        isinstance(ref, dict)
        and (ref.get("transport") == "raw_inline_base64" or bool(ref.get("data_base64")))
        for ref in media_refs
    )
    if not has_persisted_raw_ref:
        violations.append(f"{row.get('sequence_id')}:missing_persisted_raw_media_ref")

    if has_text and has_native_raw_media:
        violations.append(f"{row.get('sequence_id')}:native_raw_media_present_with_assistant_text")
    if (not has_text) and (not has_native_raw_media):
        violations.append(f"{row.get('sequence_id')}:native_raw_media_missing_without_assistant_text")

if hint_rows == 0:
    print("not_required")
elif violations:
    raise SystemExit("native_raw_media_gate violations: " + ",".join(violations))
else:
    print("required_ok")
PY
)
  if [[ "$gate_result" == "not_required" ]]; then
    if (( REQUIRE_NATIVE_RAW_MEDIA_HINTS == 1 )); then
      die "Expected raw-inline media hints for native mapping gate validation but none were observed"
    fi
    info "No raw-inline media hints observed; native mapping gate assertion not required for this run"
  fi
fi

if (( EXPECT_RAW_MEDIA_REJECTION == 1 )); then
  info "Checking runtime raw-media rejection path (invalid artifacts degrade non-fatally)"
  sqlite_reject_tmp=$(mktemp)
  sqlite3 -json "$DB_PATH" "SELECT sequence_id, llm_data, user_data, display_data FROM messages WHERE conversation_id='$stavrobot_conversation_id' AND type='agent' ORDER BY sequence_id;" >"$sqlite_reject_tmp"
  rejection_result=$(python3 - "$sqlite_reject_tmp" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
hint_rows = 0
violations = []
for row in rows:
    ud = row.get("user_data")
    if not ud:
        continue
    try:
        parsed = json.loads(ud)
    except Exception:
        continue
    st = (parsed.get("stavrobot") or {}) if isinstance(parsed, dict) else {}
    raw = st.get("raw_payload") if isinstance(st, dict) else None
    if not isinstance(raw, dict):
        continue

    raw_artifacts = [
        item for item in (raw.get("artifacts") or [])
        if isinstance(item, dict)
        and item.get("kind") == "image"
        and (item.get("transport") == "raw_inline_base64" or bool(item.get("data_base64")))
    ]
    if not raw_artifacts:
        continue

    has_invalid = False
    for art in raw_artifacts:
        mime = str(art.get("mime_type") or "").strip().lower().split(';', 1)[0]
        if mime == "image/jpg":
            mime = "image/jpeg"
        if mime and mime not in {"image/png", "image/jpeg", "image/gif", "image/webp"}:
            has_invalid = True
            break
        data = art.get("data_base64")
        if not isinstance(data, str) or not data:
            has_invalid = True
            break
        if "%%%" in data or "not-base64" in data:
            has_invalid = True
            break
        if isinstance(art.get("byte_length"), int) and art.get("byte_length", 0) > 262144:
            has_invalid = True
            break

    if not has_invalid:
        continue

    hint_rows += 1
    unsupported = st.get("unsupported_kinds") if isinstance(st, dict) else None
    if not isinstance(unsupported, list) or not any(isinstance(v, str) and v.startswith("artifact:image:") for v in unsupported):
        violations.append(f"{row.get('sequence_id')}:missing_unsupported_kinds_reason")

    display_raw = row.get("display_data")
    display = {}
    if isinstance(display_raw, str) and display_raw:
        try:
            display = json.loads(display_raw)
        except Exception:
            display = {}
    media_refs = display.get("media_refs") if isinstance(display, dict) else None
    if not isinstance(media_refs, list):
        media_refs = []
    has_persisted_raw_ref = any(
        isinstance(ref, dict)
        and (ref.get("transport") == "raw_inline_base64" or bool(ref.get("data_base64")))
        for ref in media_refs
    )
    if has_persisted_raw_ref:
        violations.append(f"{row.get('sequence_id')}:invalid_raw_media_persisted")

    llm_raw = row.get("llm_data")
    llm = {}
    if isinstance(llm_raw, str) and llm_raw:
        try:
            llm = json.loads(llm_raw)
        except Exception:
            llm = {}
    content = llm.get("Content") if isinstance(llm, dict) else []
    if not isinstance(content, list) or len(content) == 0:
        violations.append(f"{row.get('sequence_id')}:assistant_content_missing")

if hint_rows == 0:
    print("not_required")
elif violations:
    raise SystemExit("raw_media_rejection violations: " + ",".join(violations))
else:
    print("required_ok")
PY
)
  if [[ "$rejection_result" == "not_required" ]]; then
    if (( REQUIRE_RAW_MEDIA_REJECTION_HINTS == 1 )); then
      die "Expected invalid raw-media hints for rejection validation but none were observed"
    fi
    info "No invalid raw-media hints observed; rejection assertion not required for this run"
  fi
fi

if (( EXPECT_S2_MARKDOWN_TOOL_SUMMARY == 1 )); then
  info "Checking S2 markdown/tool_summary persistence behavior"
  sqlite_s2_tmp=$(mktemp)
  sqlite3 -json "$DB_PATH" "SELECT sequence_id, llm_data, user_data, display_data FROM messages WHERE conversation_id='$stavrobot_conversation_id' AND type='agent' ORDER BY sequence_id;" >"$sqlite_s2_tmp"
  s2_result=$(python3 - "$sqlite_s2_tmp" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
hint_rows = 0
violations = []
needle = "## S2 fixture heading"
for row in rows:
    ud = row.get("user_data")
    if not ud:
        continue
    try:
        parsed = json.loads(ud)
    except Exception:
        continue
    st = (parsed.get("stavrobot") or {}) if isinstance(parsed, dict) else {}
    raw = st.get("raw_payload") if isinstance(st, dict) else None
    if not isinstance(raw, dict):
        continue

    content_items = raw.get("content") or []
    if not isinstance(content_items, list):
        content_items = []
    has_markdown_hint = any(
        isinstance(item, dict)
        and item.get("kind") == "markdown"
        and isinstance(item.get("text"), str)
        and needle in item.get("text")
        for item in content_items
    )

    display_hint = raw.get("display") if isinstance(raw.get("display"), dict) else {}
    has_tool_summary_hint = isinstance(display_hint.get("tool_summary"), list) and len(display_hint.get("tool_summary")) > 0

    if not (has_markdown_hint and has_tool_summary_hint):
        continue

    hint_rows += 1

    llm_raw = row.get("llm_data")
    llm = {}
    if isinstance(llm_raw, str) and llm_raw:
        try:
            llm = json.loads(llm_raw)
        except Exception:
            llm = {}
    llm_content = llm.get("Content") if isinstance(llm, dict) else []
    if not isinstance(llm_content, list):
        llm_content = []

    has_llm_text = any(
        isinstance(item, dict)
        and isinstance(item.get("Text"), str)
        and needle in item.get("Text")
        for item in llm_content
    )
    if not has_llm_text:
        violations.append(f"{row.get('sequence_id')}:llm_content_missing_s2_markdown")

    display_raw = row.get("display_data")
    if not display_raw:
        violations.append(f"{row.get('sequence_id')}:display_data_missing")
        continue
    try:
        display = json.loads(display_raw)
    except Exception:
        violations.append(f"{row.get('sequence_id')}:display_data_invalid_json")
        continue
    tool_summary = display.get("tool_summary") if isinstance(display, dict) else None
    if not isinstance(tool_summary, list) or not tool_summary:
        violations.append(f"{row.get('sequence_id')}:display_tool_summary_missing")

if hint_rows == 0:
    print("not_required")
elif violations:
    raise SystemExit("s2_markdown_tool_summary violations: " + ",".join(violations))
else:
    print("required_ok")
PY
)
  if [[ "$s2_result" == "not_required" ]]; then
    if (( REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS == 1 )); then
      die "Expected S2 markdown/tool_summary hints but none were observed"
    fi
    info "No S2 markdown/tool_summary hints observed; assertion not required for this run"
  fi
fi

if (( EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK == 1 )); then
  info "Checking S2 tool_summary raw-events fallback behavior"
  sqlite_s2_fallback_tmp=$(mktemp)
  sqlite3 -json "$DB_PATH" "SELECT sequence_id, llm_data, user_data, display_data FROM messages WHERE conversation_id='$stavrobot_conversation_id' AND type='agent' ORDER BY sequence_id;" >"$sqlite_s2_fallback_tmp"
  s2_fallback_result=$(python3 - "$sqlite_s2_fallback_tmp" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
hint_rows = 0
violations = []
for row in rows:
    ud = row.get("user_data")
    if not ud:
        continue
    try:
        parsed = json.loads(ud)
    except Exception:
        continue
    st = (parsed.get("stavrobot") or {}) if isinstance(parsed, dict) else {}
    raw = st.get("raw_payload") if isinstance(st, dict) else None
    if not isinstance(raw, dict):
        continue

    raw_events = raw.get("raw", {}).get("events") if isinstance(raw.get("raw"), dict) else None
    if not isinstance(raw_events, list) or not raw_events:
        continue

    display_hint = raw.get("display") if isinstance(raw.get("display"), dict) else {}
    has_direct_tool_summary_hint = isinstance(display_hint.get("tool_summary"), list) and len(display_hint.get("tool_summary")) > 0
    if has_direct_tool_summary_hint:
        continue

    hint_rows += 1

    display_raw = row.get("display_data")
    if not display_raw:
        violations.append(f"{row.get('sequence_id')}:display_data_missing")
        continue
    try:
        display = json.loads(display_raw)
    except Exception:
        violations.append(f"{row.get('sequence_id')}:display_data_invalid_json")
        continue
    tool_summary = display.get("tool_summary") if isinstance(display, dict) else None
    if not isinstance(tool_summary, list) or not tool_summary:
        violations.append(f"{row.get('sequence_id')}:display_tool_summary_missing_from_raw_events")

if hint_rows == 0:
    print("not_required")
elif violations:
    raise SystemExit("s2_tool_summary_raw_fallback violations: " + ",".join(violations))
else:
    print("required_ok")
PY
)
  if [[ "$s2_fallback_result" == "not_required" ]]; then
    if (( REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS == 1 )); then
      die "Expected S2 raw-events tool_summary fallback hints but none were observed"
    fi
    info "No S2 raw-events tool_summary fallback hints observed; assertion not required for this run"
  fi
fi

info "Managed Shelley S1 smoke test passed"
info "Normal conversation: $normal_conversation_id"
info "Stavrobot conversation: $stavrobot_conversation_id"
info "DB path: $DB_PATH"
info "Server log: $SERVER_LOG"
