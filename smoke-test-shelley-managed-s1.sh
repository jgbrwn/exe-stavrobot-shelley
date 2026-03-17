#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

SHELLEY_DIR="${SHELLEY_DIR:-/opt/shelley}"
SHELLEY_BIN=""
PORT="8765"
DB_PATH="/tmp/shelley-stavrobot-managed-test.db"
BASE_URL=""
STAVROBOT_BASE_URL="${STAVROBOT_BASE_URL:-http://localhost:8000}"
STAVROBOT_CONFIG_PATH="${STAVROBOT_CONFIG_PATH:-/tmp/stavrobot/data/main/config.toml}"
BRIDGE_PROFILE="local-default"
NORMAL_EXPECTED="managed normal control ok"
STAVROBOT_EXPECTED="managed spike first turn ok"
STAVROBOT_SECOND_EXPECTED="managed spike second turn ok"
TMUX_SESSION="shelley-managed-s1-smoke"
KEEP_SERVER=0
SERVER_LOG="/tmp/shelley-managed-s1-smoke.log"

usage() {
  cat <<'EOF'
Usage: ./smoke-test-shelley-managed-s1.sh [flags]

Flags:
  --shelley-dir PATH             Shelley checkout/build dir (default: /opt/shelley or SHELLEY_DIR)
  --shelley-bin PATH             Shelley binary path (default: SHELLEY_DIR/bin/shelley)
  --port PORT                    Test port (default: 8765)
  --db-path PATH                 Test sqlite db path
  --stavrobot-base-url URL       Stavrobot base URL (default: http://localhost:8000)
  --stavrobot-config-path PATH   Stavrobot config path used by bridge profile assumptions
  --bridge-profile NAME          Bridge profile name for Stavrobot conversation (default: local-default)
  --tmux-session NAME            tmux session name used for test server
  --keep-server                  Leave test Shelley server running after success
  --help

Notes:
  - assumes the Shelley build already contains a Stavrobot-capable S1 patch
  - starts an isolated Shelley server on a safe port with its own DB
  - validates both normal Shelley behavior and Stavrobot-mode behavior
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
[[ -f "$STAVROBOT_CONFIG_PATH" ]] || die "Stavrobot config path not found: $STAVROBOT_CONFIG_PATH"
[[ "$PORT" =~ ^[0-9]+$ ]] || die "--port must be numeric"

BASE_URL="http://localhost:$PORT"
rm -f "$DB_PATH" "$SERVER_LOG"
tmux kill-session -t "$TMUX_SESSION" >/dev/null 2>&1 || true

info "Starting isolated Shelley test server on port $PORT"
tmux new-session -d -s "$TMUX_SESSION" \
  "cd '$SHELLEY_DIR' && '$SHELLEY_BIN' -predictable-only -default-model predictable -model predictable -db '$DB_PATH' serve -port '$PORT' -socket none >'$SERVER_LOG' 2>&1"

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
python3 - "$normal_conv_tmp" "$NORMAL_EXPECTED" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
needle = sys.argv[2]
messages = data.get("messages", [])
texts = []
for msg in messages:
    for item in msg.get("content", []):
        if isinstance(item, dict) and item.get("Text"):
            texts.append(item.get("Text"))
joined = "\n".join(texts)
if needle not in joined:
    raise SystemExit(f"normal control conversation did not include expected text: {needle}")
PY

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
python3 - "$stavrobot_conv_tmp" "$STAVROBOT_EXPECTED" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
needle = sys.argv[2]
messages = data.get("messages", [])
texts = []
for msg in messages:
    for item in msg.get("content", []):
        if isinstance(item, dict) and item.get("Text"):
            texts.append(item.get("Text"))
joined = "\n".join(texts)
if needle not in joined:
    raise SystemExit(f"stavrobot first turn did not include expected text: {needle}")
PY

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
python3 - "$stavrobot_conv_tmp2" "$STAVROBOT_SECOND_EXPECTED" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
needle = sys.argv[2]
messages = data.get("messages", [])
texts = []
for msg in messages:
    for item in msg.get("content", []):
        if isinstance(item, dict) and item.get("Text"):
            texts.append(item.get("Text"))
joined = "\n".join(texts)
if needle not in joined:
    raise SystemExit(f"stavrobot second turn did not include expected text: {needle}")
PY

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

info "Managed Shelley S1 smoke test passed"
info "Normal conversation: $normal_conversation_id"
info "Stavrobot conversation: $stavrobot_conversation_id"
info "DB path: $DB_PATH"
info "Server log: $SERVER_LOG"
