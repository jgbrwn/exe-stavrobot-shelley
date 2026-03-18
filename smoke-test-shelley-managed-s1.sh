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
BRIDGE_FIXTURE=""
SERVER_LOG="/tmp/shelley-managed-s1-smoke.log"

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
  --expect-media-refs            Assert persisted display_data.media_refs when artifact/image hints are present
  --require-media-refs           With --expect-media-refs, fail if no media-ref hints are observed
  --bridge-fixture NAME          Optional bridge fixture mode for smoke server (e.g. tool_summary)
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

python3 "$ROOT_DIR/py/shelley_bridge_profiles.py" validate "$PROFILE_STATE_PATH" >/dev/null
python3 "$ROOT_DIR/py/shelley_bridge_profiles.py" resolve "$PROFILE_STATE_PATH" "$BRIDGE_PROFILE" >/dev/null

BASE_URL="http://localhost:$PORT"
rm -f "$DB_PATH" "$SERVER_LOG"
tmux kill-session -t "$TMUX_SESSION" >/dev/null 2>&1 || true

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
    for item in (raw.get("content") or []):
        if isinstance(item, dict) and item.get("kind") == "image_ref" and item.get("url"):
            has_hint = True
            break
    if not has_hint:
        for item in (raw.get("artifacts") or []):
            if isinstance(item, dict) and item.get("kind") == "image" and item.get("url"):
                has_hint = True
                break

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

info "Managed Shelley S1 smoke test passed"
info "Normal conversation: $normal_conversation_id"
info "Stavrobot conversation: $stavrobot_conversation_id"
info "DB path: $DB_PATH"
info "Server log: $SERVER_LOG"
