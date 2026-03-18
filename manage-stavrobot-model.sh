#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

STAVROBOT_DIR=""
CONFIG_PATH=""
BASE_URL="${STAVROBOT_BASE_URL:-http://localhost:8000}"
TIMEOUT=60
POLL_INTERVAL=2
ACTION=""
MODEL=""
STAVROBOT_CLIENT_BIN="${STAVROBOT_CLIENT_BIN:-$ROOT_DIR/client-stavrobot.sh}"
OPENROUTER_MODELS_SCRIPT="${OPENROUTER_MODELS_SCRIPT:-$ROOT_DIR/py/openrouter_models.py}"

usage() {
  cat <<'EOF'
Usage: ./manage-stavrobot-model.sh <action> [flags]

Actions:
  get-current
  list-openrouter-free
  apply --model MODEL_ID

Flags:
  --stavrobot-dir PATH   Use PATH/data/main/config.toml and docker compose there
  --config-path PATH     Explicit config.toml path
  --base-url URL         Stavrobot base URL (default: STAVROBOT_BASE_URL or http://localhost:8000)
  --timeout SEC          Health wait timeout for apply (default: 60)
  --poll-interval SEC    Health poll interval for apply (default: 2)
  --model MODEL_ID       Model to apply
  --help

Environment:
  STAVROBOT_CLIENT_BIN     Override client helper used for health checks
  OPENROUTER_MODELS_SCRIPT Override OpenRouter model catalog script
EOF
}

resolve_config_path() {
  if [[ -z "$CONFIG_PATH" && -n "$STAVROBOT_DIR" ]]; then
    CONFIG_PATH="$STAVROBOT_DIR/data/main/config.toml"
  fi
  [[ -n "$CONFIG_PATH" ]] || die "Provide --config-path or --stavrobot-dir"
  [[ -f "$CONFIG_PATH" ]] || die "Config file not found: $CONFIG_PATH"
}

require_action() {
  [[ -n "$ACTION" ]] || die "Specify an action"
}

get_current_json() {
  python3 "$ROOT_DIR/py/stavrobot_model_control.py" get-current "$CONFIG_PATH"
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

ensure_openrouter_active() {
  local tmp
  tmp=$(mktemp)
  get_current_json >"$tmp"
  local available provider reason
  available=$(json_field "$tmp" openrouter_model_selection_available)
  provider=$(json_field "$tmp" provider)
  reason=$(json_field "$tmp" reason)
  if [[ "$available" != "true" ]]; then
    python3 - "$provider" "$reason" <<'PY'
import json, sys
provider, reason = sys.argv[1], sys.argv[2]
print(json.dumps({
  "status": "error",
  "error": "openrouter_not_active",
  "provider": provider,
  "reason": reason,
  "message": "OpenRouter model selection is unavailable because Stavrobot is not currently configured with provider = openrouter and corresponding auth/config."
}, indent=2))
PY
    rm -f "$tmp"
    exit 1
  fi
  rm -f "$tmp"
}

health_json() {
  "$STAVROBOT_CLIENT_BIN" \
    --config-path "$CONFIG_PATH" \
    --base-url "$BASE_URL" \
    --request-timeout 30 \
    --connect-timeout 5 \
    health
}

wait_for_health_model() {
  local expected_provider="$1"
  local expected_model="$2"
  local deadline now tmp ok provider model
  deadline=$(( $(date +%s) + TIMEOUT ))
  while true; do
    tmp=$(mktemp)
    if health_json >"$tmp" 2>/dev/null; then
      ok=$(json_field "$tmp" ok)
      provider=$(json_field "$tmp" provider)
      model=$(json_field "$tmp" model)
      if [[ "$ok" == "true" && "$provider" == "$expected_provider" && "$model" == "$expected_model" ]]; then
        cat "$tmp"
        rm -f "$tmp"
        return 0
      fi
    fi
    rm -f "$tmp"
    now=$(date +%s)
    if (( now >= deadline )); then
      return 1
    fi
    sleep "$POLL_INTERVAL"
  done
}

list_openrouter_free() {
  ensure_openrouter_active
  python3 - "$OPENROUTER_MODELS_SCRIPT" <<'PY'
import json, subprocess, sys
out = subprocess.check_output(["python3", sys.argv[1]], text=True)
payload = json.loads(out)
payload = {
  "status": "ok",
  "source": "openrouter-free",
  "provider": "openrouter",
  "models": payload.get("models", []),
}
print(json.dumps(payload, indent=2))
PY
}

apply_model() {
  [[ -n "$MODEL" ]] || die "apply requires --model"
  ensure_openrouter_active

  local before tmp previous_model provider health_out operation
  tmp=$(mktemp)
  get_current_json >"$tmp"
  previous_model=$(json_field "$tmp" model)
  provider=$(json_field "$tmp" provider)
  rm -f "$tmp"

  python3 "$ROOT_DIR/py/stavrobot_model_control.py" set-model "$CONFIG_PATH" "$MODEL" >/dev/null

  if [[ -n "$STAVROBOT_DIR" ]]; then
    if ! (cd "$STAVROBOT_DIR" && docker compose restart app >/dev/null); then
      python3 - "$previous_model" "$MODEL" <<'PY'
import json, sys
print(json.dumps({
  "status": "error",
  "error": "restart_failed",
  "previous_model": sys.argv[1],
  "attempted_model": sys.argv[2],
  "operation": "restart",
  "ready": False,
  "message": "Failed to restart Stavrobot app service."
}, indent=2))
PY
      exit 1
    fi
    operation="restart"
  else
    die "apply currently requires --stavrobot-dir so docker compose can be run safely"
  fi

  if health_out=$(wait_for_health_model "$provider" "$MODEL"); then
    python3 - "$previous_model" "$MODEL" "$operation" "$health_out" <<'PY'
import json, sys
print(json.dumps({
  "status": "ok",
  "operation": sys.argv[3],
  "previous_model": sys.argv[1],
  "current_model": sys.argv[2],
  "provider": json.loads(sys.argv[4]).get("provider", ""),
  "ready": True,
  "health": json.loads(sys.argv[4]),
}, indent=2))
PY
    return 0
  fi

  if (cd "$STAVROBOT_DIR" && docker compose up -d --force-recreate app >/dev/null); then
    operation="force-recreate"
    if health_out=$(wait_for_health_model "$provider" "$MODEL"); then
      python3 - "$previous_model" "$MODEL" "$operation" "$health_out" <<'PY'
import json, sys
print(json.dumps({
  "status": "ok",
  "operation": sys.argv[3],
  "previous_model": sys.argv[1],
  "current_model": sys.argv[2],
  "provider": json.loads(sys.argv[4]).get("provider", ""),
  "ready": True,
  "health": json.loads(sys.argv[4]),
}, indent=2))
PY
      return 0
    fi
  fi

  python3 - "$previous_model" "$MODEL" <<'PY'
import json, sys
print(json.dumps({
  "status": "error",
  "error": "health_timeout",
  "previous_model": sys.argv[1],
  "attempted_model": sys.argv[2],
  "operation": "force-recreate",
  "ready": False,
  "message": "Timed out waiting for Stavrobot health after model change."
}, indent=2))
PY
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    get-current|list-openrouter-free|apply)
      [[ -z "$ACTION" ]] || die "Only one action may be specified"
      ACTION="$1"
      shift
      ;;
    --stavrobot-dir)
      STAVROBOT_DIR="$2"
      shift 2
      ;;
    --config-path)
      CONFIG_PATH="$2"
      shift 2
      ;;
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --poll-interval)
      POLL_INTERVAL="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
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

require_action
resolve_config_path
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die "--timeout must be an integer"
[[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]] || die "--poll-interval must be an integer"

case "$ACTION" in
  get-current)
    get_current_json
    ;;
  list-openrouter-free)
    list_openrouter_free
    ;;
  apply)
    apply_model
    ;;
esac
