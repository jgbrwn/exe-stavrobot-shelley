#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

SHELLEY_DIR="${SHELLEY_DIR:-/opt/shelley}"
SHELLEY_BIN=""
PROFILE_STATE_PATH="${PROFILE_STATE_PATH:-$ROOT_DIR/state/shelley-bridge-profiles.json}"
BRIDGE_PROFILE="local-default"
PORT="8922"
DB_PATH=""
TMUX_SESSION=""
OUTPUT_JSON="$ROOT_DIR/state/s4-recall-validation-last.json"
SERVER_LOG="/tmp/shelley-s4-recall-validation.log"
KEEP_SERVER=0
REQUIRE_REMOTE_ISOLATION=0

find_port_listener() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "sport = :$PORT" 2>/dev/null | awk 'NR>1 {print}' || true
    return
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | tail -n +2 || true
    return
  fi
}

cleanup() {
  if (( KEEP_SERVER == 0 )); then
    tmux kill-session -t "$TMUX_SESSION" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage: ./run-shelley-managed-s4-recall-validation.sh [flags]

Runs a repeatable managed Shelley S4 recall validation matrix and writes a machine-readable report.

Flags:
  --shelley-dir PATH         Shelley checkout dir (default: /opt/shelley)
  --shelley-bin PATH         Shelley binary path (default: SHELLEY_DIR/bin/shelley)
  --profile-state-path PATH  Bridge-profile state file
  --bridge-profile NAME      Stavrobot bridge profile for recall conversations (default: local-default)
  --port PORT                Isolated validation server port (default: 8922; must not be 9999)
  --db-path PATH             SQLite DB path (default: /tmp/shelley-s4-recall-PORT-TIMESTAMP.db)
  --tmux-session NAME        tmux session name (default: shelley-s4-recall-PORT-TIMESTAMP)
  --output-json PATH         Report output path (default: state/s4-recall-validation-last.json)
  --require-remote-isolation Fail run if all seeded Shelley conversations do not map to distinct remote Stavrobot conversation IDs
  --keep-server              Leave validation server running after completion
  --help
USAGE
}

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
    --profile-state-path)
      PROFILE_STATE_PATH="$2"
      shift 2
      ;;
    --bridge-profile)
      BRIDGE_PROFILE="$2"
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
    --tmux-session)
      TMUX_SESSION="$2"
      shift 2
      ;;
    --output-json)
      OUTPUT_JSON="$2"
      shift 2
      ;;
    --require-remote-isolation)
      REQUIRE_REMOTE_ISOLATION=1
      shift
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
require_cmd sqlite3
require_cmd python3

[[ "$PORT" =~ ^[0-9]+$ ]] || die "--port must be numeric"
if (( PORT == 9999 )); then
  die "--port 9999 is reserved for operator/dev Shelley; choose a dedicated validation port"
fi

[[ -n "$SHELLEY_BIN" ]] || SHELLEY_BIN="$SHELLEY_DIR/bin/shelley"
[[ -x "$SHELLEY_BIN" ]] || die "Shelley binary not found or not executable: $SHELLEY_BIN"
[[ -f "$PROFILE_STATE_PATH" ]] || die "Profile state file not found: $PROFILE_STATE_PATH"
python3 "$ROOT_DIR/py/shelley_bridge_profiles.py" validate "$PROFILE_STATE_PATH" >/dev/null
python3 "$ROOT_DIR/py/shelley_bridge_profiles.py" resolve "$PROFILE_STATE_PATH" "$BRIDGE_PROFILE" >/dev/null

stamp=$(date +%s)
[[ -n "$DB_PATH" ]] || DB_PATH="/tmp/shelley-s4-recall-${PORT}-${stamp}.db"
[[ -n "$TMUX_SESSION" ]] || TMUX_SESSION="shelley-s4-recall-${PORT}-${stamp}"
BASE_URL="http://localhost:$PORT"

rm -f "$DB_PATH" "$SERVER_LOG"
tmux kill-session -t "$TMUX_SESSION" >/dev/null 2>&1 || true

listener=$(find_port_listener)
[[ -z "$listener" ]] || die "Port $PORT already in use; choose another --port"

info "Starting isolated Shelley S4 recall validation server on port $PORT"
tmux new-session -d -s "$TMUX_SESSION" \
  "cd '$SHELLEY_DIR' && '$SHELLEY_BIN' -predictable-only -default-model predictable -model predictable -db '$DB_PATH' serve -port '$PORT' -socket none >'$SERVER_LOG' 2>&1"

for _ in $(seq 1 30); do
  if curl -fsS "$BASE_URL/" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS "$BASE_URL/" >/dev/null 2>&1 || die "Shelley validation server did not become ready"

meta_json=$(python3 - "$stamp" <<'PY'
import json,sys
stamp=sys.argv[1]
out={
  "stamp": stamp,
  "facts": {
    "A": f"S4_FACT_A_{stamp}",
    "B": f"S4_FACT_B_{stamp}",
    "C": f"S4_FACT_C_{stamp}",
  }
}
print(json.dumps(out))
PY
)

create_payload=$(python3 - "$meta_json" "$BRIDGE_PROFILE" <<'PY'
import json,sys
meta=json.loads(sys.argv[1])
profile=sys.argv[2]
facts=meta["facts"]

def mk(name,fact,topic):
    return {
      "message": f"Memory seed for S4 validation. Remember exact token {fact}. Topic: {topic}. Reply by echoing token {fact} exactly once.",
      "conversation_options": {
        "type": "stavrobot",
        "stavrobot": {"enabled": True, "bridge_profile": profile},
      },
      "_name": name,
      "_fact": fact,
    }
out=[mk("A",facts["A"],"plugin choice discussion"), mk("B",facts["B"],"model/provider setup discussion"), mk("C",facts["C"],"managed rebuild status discussion")]
print(json.dumps(out))
PY
)

post_json() {
  local path="$1"
  local payload="$2"
  curl -sS -X POST "$BASE_URL$path" -H 'Content-Type: application/json' -d "$payload"
}

json_field() {
  local file="$1"
  local path="$2"
  python3 - "$file" "$path" <<'PY'
import json,sys
with open(sys.argv[1]) as f:
    data=json.load(f)
cur=data
for part in sys.argv[2].split('.'):
    if not part:
        continue
    if isinstance(cur,dict) and part in cur:
        cur=cur[part]
    else:
        print("")
        raise SystemExit(0)
print(cur if cur is not None else "")
PY
}

get_last_assistant_text() {
  local convo_id="$1"
  local out_file
  out_file=$(mktemp)
  curl -sS "$BASE_URL/api/conversation/$convo_id" >"$out_file"
  python3 - "$out_file" <<'PY'
import json,sys
try:
    with open(sys.argv[1]) as f:
        data=json.load(f)
except Exception:
    print("")
    raise SystemExit(0)
msgs=data.get("messages") or []
for msg in reversed(msgs):
    for item in msg.get("content") or []:
        if isinstance(item,dict):
            txt=item.get("Text") or item.get("text")
            if isinstance(txt,str) and txt.strip():
                print(txt.strip())
                raise SystemExit(0)
    raw = msg.get("llm_data")
    if raw:
        try:
            parsed = json.loads(raw) if isinstance(raw, str) else raw
        except Exception:
            parsed = None
        if isinstance(parsed, dict):
            for item in parsed.get("Content", []) or []:
                if isinstance(item, dict):
                    txt = item.get("Text") or item.get("text")
                    if isinstance(txt, str) and txt.strip():
                        print(txt.strip())
                        raise SystemExit(0)
print("")
PY
  rm -f "$out_file"
}

# Create seed conversations A/B/C
seed_json=$(mktemp)
python3 - "$create_payload" > "$seed_json" <<'PY'
import json,sys
print(json.dumps(json.loads(sys.argv[1])))
PY

conv_a=""
conv_b=""
conv_c=""

for idx in 0 1 2; do
  payload=$(python3 - "$seed_json" "$idx" <<'PY'
import json,sys
arr=json.load(open(sys.argv[1]))
print(json.dumps({k:v for k,v in arr[int(sys.argv[2])].items() if not k.startswith('_')}))
PY
)
  resp_tmp=$(mktemp)
  post_json "/api/conversations/new" "$payload" > "$resp_tmp"
  cid=$(json_field "$resp_tmp" conversation_id)
  [[ -n "$cid" ]] || die "failed creating seed conversation index=$idx"
  case "$idx" in
    0) conv_a="$cid" ;;
    1) conv_b="$cid" ;;
    2) conv_c="$cid" ;;
  esac
  sleep 2
done

# Probes: same-thread, cross-thread, time-separated, tool/event-heavy-ish
probe_results=$(python3 - "$meta_json" "$conv_a" "$conv_b" "$conv_c" <<'PY'
import json,sys
meta=json.loads(sys.argv[1])
out={
  "facts":meta["facts"],
  "conversations":{"A":sys.argv[2],"B":sys.argv[3],"C":sys.argv[4]},
  "probes":[
    {
      "scenario":"single-thread",
      "from":"A",
      "prompt":"What exact token did I ask you to remember at the start of this conversation? Reply with token only.",
      "expected":[meta["facts"]["A"]],
      "scope_target":"active_conversation_only",
    },
    {
      "scenario":"cross-thread",
      "from":"C",
      "prompt":"From our other conversations, what were the exact memory tokens for plugin-choice and model/provider setup discussions?",
      "expected":[meta["facts"]["A"],meta["facts"]["B"]],
      "scope_target":"appears_cross_conversation",
    },
    {
      "scenario":"time-separated",
      "from":"B",
      "prompt":"Earlier we discussed a memory seed before now. What was the exact token?",
      "expected":[meta["facts"]["B"]],
      "scope_target":"active_conversation_only",
    },
    {
      "scenario":"tool-event-heavy",
      "from":"A",
      "prompt":"If you can recall prior tool/event-oriented details, name the exact memory token for this thread.",
      "expected":[meta["facts"]["A"]],
      "scope_target":"unclear_scope",
    },
  ],
}
print(json.dumps(out))
PY
)

probe_json=$(mktemp)
printf '%s\n' "$probe_results" > "$probe_json"

for idx in 0 1 2 3; do
  cid=$(python3 - "$probe_json" "$idx" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
frm=data['probes'][int(sys.argv[2])]['from']
print(data['conversations'][frm])
PY
)
  prompt=$(python3 - "$probe_json" "$idx" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
print(data['probes'][int(sys.argv[2])]['prompt'])
PY
)
  payload=$(python3 - "$prompt" <<'PY'
import json,sys
print(json.dumps({"message":sys.argv[1]}))
PY
)
  post_json "/api/conversation/$cid/chat" "$payload" >/dev/null
  sleep 2
  answer=$(get_last_assistant_text "$cid")
  python3 - "$probe_json" "$idx" "$answer" > "$probe_json.next" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
idx=int(sys.argv[2])
ans=sys.argv[3]
data['probes'][idx]['answer']=ans
print(json.dumps(data))
PY
  mv "$probe_json.next" "$probe_json"
done

# Join remote conversation ids for evidence
sqlite_tmp=$(mktemp)
sqlite3 -json "$DB_PATH" "SELECT conversation_id, conversation_options FROM conversations WHERE conversation_id IN ('$conv_a','$conv_b','$conv_c') ORDER BY conversation_id;" > "$sqlite_tmp"

python3 - "$probe_json" "$sqlite_tmp" "$OUTPUT_JSON" "$SHELLEY_BIN" "$PROFILE_STATE_PATH" "$BRIDGE_PROFILE" "$PORT" "$DB_PATH" "$SERVER_LOG" "$REQUIRE_REMOTE_ISOLATION" <<'PY'
import json,sys,datetime,re
from datetime import timezone
probes=json.load(open(sys.argv[1]))
rows=json.load(open(sys.argv[2]))
out_path=sys.argv[3]
require_remote_isolation = sys.argv[10] == '1'

bridge_map={}
for r in rows:
    co=r.get('conversation_options')
    if not isinstance(co,str):
        continue
    try:
        parsed=json.loads(co)
    except Exception:
        continue
    st=(parsed.get('stavrobot') or {}) if isinstance(parsed,dict) else {}
    bridge_map[r.get('conversation_id')] = st.get('conversation_id')

for p in probes['probes']:
    ans=(p.get('answer') or '')
    expected=p.get('expected') or []
    hits=[t for t in expected if isinstance(t,str) and t and t in ans]
    if hits and len(hits)==len(expected):
        acc='correct'
    elif hits:
        acc='partially_correct'
    elif re.search(r"\b(i (do not|don't) know|not sure|cannot recall)\b", ans, re.I):
        acc='claims_not_to_know'
    elif not ans.strip():
        acc='unclear'
    else:
        acc='incorrect'
    p['accuracy']=acc

    scope='unclear_scope'
    if p['scenario']=='cross-thread':
        scope='appears_cross_conversation' if hits else 'active_conversation_only'
    elif p['scenario'] in ('single-thread','time-separated'):
        scope='active_conversation_only' if hits else 'unclear_scope'
    p['scope_behavior']=scope

    if acc=='correct':
        ux='acceptable'
    elif acc in ('partially_correct','claims_not_to_know'):
        ux='borderline'
    else:
        ux='confusing'
    p['ux_quality']=ux

    frm=p.get('from')
    cid=probes['conversations'].get(frm)
    p['conversation_id']=cid
    p['remote_stavrobot_conversation_id']=bridge_map.get(cid)

cross=[p for p in probes['probes'] if p.get('scenario')=='cross-thread']
cross_good=sum(1 for p in cross if p.get('accuracy') in ('correct','partially_correct'))
outcome='S4A' if cross and cross_good/len(cross) >= 0.6 else 'S4B'
confidence='medium' if len(probes['probes']) >= 4 else 'low'

remote_ids = sorted({rid for rid in bridge_map.values() if isinstance(rid, str) and rid})
remote_isolation_ok = len(remote_ids) >= len(probes['conversations'])

report={
  'schema_version':1,
  'generated_at':datetime.datetime.now(timezone.utc).isoformat().replace('+00:00','Z'),
  'metadata':{
    'shelley_bin':sys.argv[4],
    'profile_state_path':sys.argv[5],
    'bridge_profile':sys.argv[6],
    'port':int(sys.argv[7]),
    'db_path':sys.argv[8],
    'server_log':sys.argv[9],
    'path_used':'managed Shelley API',
    'require_remote_isolation': require_remote_isolation,
    'remote_isolation_ok': remote_isolation_ok,
    'remote_stavrobot_conversation_ids': remote_ids,
  },
  'facts':probes['facts'],
  'conversations':probes['conversations'],
  'probes':probes['probes'],
  'decision':{
    'provisional_outcome':outcome,
    'confidence':confidence,
    'rationale':'Automated token-match heuristic; review probe answers manually before product decisions.',
  },
}

import os
os.makedirs(os.path.dirname(out_path), exist_ok=True)
if require_remote_isolation and not remote_isolation_ok:
    raise SystemExit('remote isolation check failed: expected distinct remote Stavrobot conversation IDs per seeded Shelley conversation')

with open(out_path,'w') as f:
    json.dump(report,f,indent=2,sort_keys=True)
    f.write('\n')
print(out_path)
PY

info "S4 recall validation report written: $OUTPUT_JSON"
info "DB path: $DB_PATH"
info "Server log: $SERVER_LOG"
if (( KEEP_SERVER == 1 )); then
  info "Server kept running (tmux session: $TMUX_SESSION)"
fi
