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
PROFILE=""
PROFILES_PATH="${ROOT_DIR}/state/llm-profiles.json"
STAVROBOT_CLIENT_BIN="${STAVROBOT_CLIENT_BIN:-$ROOT_DIR/client-stavrobot.sh}"
OPENROUTER_MODELS_SCRIPT="${OPENROUTER_MODELS_SCRIPT:-$ROOT_DIR/py/openrouter_models.py}"

usage() {
  cat <<'EOF'
Usage: ./manage-stavrobot-model.sh <action> [flags]

Actions:
  get-current
  list-openrouter-free
  apply --model MODEL_ID
  list-profiles
  apply-profile --profile PROFILE_ID

Flags:
  --stavrobot-dir PATH   Use PATH/data/main/config.toml and docker compose there
  --config-path PATH     Explicit config.toml path
  --profiles-path PATH   LLM profiles JSON path (default: ./state/llm-profiles.json)
  --base-url URL         Stavrobot base URL (default: STAVROBOT_BASE_URL or http://localhost:8000)
  --timeout SEC          Health wait timeout for apply (default: 60)
  --poll-interval SEC    Health poll interval for apply (default: 2)
  --model MODEL_ID       Model to apply (for action=apply)
  --profile PROFILE_ID   Profile id to apply (for action=apply-profile)
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

require_stavrobot_dir_for_restart() {
  [[ -n "$STAVROBOT_DIR" ]] || die "This action requires --stavrobot-dir so docker compose can restart app"
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

restart_and_wait() {
  local expected_provider="$1"
  local expected_model="$2"

  local health_out operation
  if ! (cd "$STAVROBOT_DIR" && docker compose restart app >/dev/null); then
    python3 - "$expected_provider" "$expected_model" <<'PY'
import json, sys
print(json.dumps({
  "status": "error",
  "error": "restart_failed",
  "provider": sys.argv[1],
  "attempted_model": sys.argv[2],
  "operation": "restart",
  "ready": False,
  "message": "Failed to restart Stavrobot app service."
}, indent=2))
PY
    exit 1
  fi
  operation="restart"

  if health_out=$(wait_for_health_model "$expected_provider" "$expected_model"); then
    python3 - "$expected_model" "$operation" "$health_out" <<'PY'
import json, sys
print(json.dumps({
  "status": "ok",
  "operation": sys.argv[2],
  "current_model": sys.argv[1],
  "provider": json.loads(sys.argv[3]).get("provider", ""),
  "ready": True,
  "health": json.loads(sys.argv[3]),
}, indent=2))
PY
    return 0
  fi

  if (cd "$STAVROBOT_DIR" && docker compose up -d --force-recreate app >/dev/null); then
    operation="force-recreate"
    if health_out=$(wait_for_health_model "$expected_provider" "$expected_model"); then
      python3 - "$expected_model" "$operation" "$health_out" <<'PY'
import json, sys
print(json.dumps({
  "status": "ok",
  "operation": sys.argv[2],
  "current_model": sys.argv[1],
  "provider": json.loads(sys.argv[3]).get("provider", ""),
  "ready": True,
  "health": json.loads(sys.argv[3]),
}, indent=2))
PY
      return 0
    fi
  fi

  python3 - "$expected_provider" "$expected_model" <<'PY'
import json, sys
print(json.dumps({
  "status": "error",
  "error": "health_timeout",
  "provider": sys.argv[1],
  "attempted_model": sys.argv[2],
  "operation": "force-recreate",
  "ready": False,
  "message": "Timed out waiting for Stavrobot health after model/provider change."
}, indent=2))
PY
  return 1
}

list_openrouter_free() {
  ensure_openrouter_active
  python3 - "$OPENROUTER_MODELS_SCRIPT" <<'PY'
import json, subprocess, sys

def display_context(v):
  if isinstance(v, int) and v > 0:
    if v >= 1_000_000:
      return f"{v/1_000_000:.1f}M tokens"
    if v >= 1_000:
      return f"{v/1_000:.0f}k tokens"
    return f"{v} tokens"
  return "unknown"

out = subprocess.check_output(["python3", sys.argv[1]], text=True)
raw = json.loads(out)
models = []
for item in raw.get("models", []):
  context = item.get("context_length")
  models.append({
    "id": item.get("id", ""),
    "name": item.get("name", ""),
    "context_length": context,
    "context_limit_display": display_context(context),
  })

payload = {
  "status": "ok",
  "source": "openrouter-free",
  "provider": "openrouter",
  "models": models,
}
print(json.dumps(payload, indent=2))
PY
}

list_profiles() {
  python3 - "$PROFILES_PATH" "$CONFIG_PATH" <<'PY'
import json, os, sys, tomllib
profiles_path, config_path = sys.argv[1], sys.argv[2]
profiles = {}
if os.path.exists(profiles_path):
    with open(profiles_path) as f:
        payload = json.load(f)
    profiles = payload.get("profiles", {}) if isinstance(payload, dict) else {}

cfg = tomllib.loads(open(config_path).read())
provider = cfg.get("provider", "")
model = cfg.get("model", "")
base_url = cfg.get("baseUrl", "")
active = ""
for pid, p in profiles.items():
    if not isinstance(p, dict):
        continue
    if p.get("provider") == provider and p.get("model") == model:
        p_base = p.get("baseUrl", "")
        if p_base == base_url:
            active = pid
            break

print(json.dumps({
    "status": "ok",
    "active_profile": active,
    "profiles": profiles,
}, indent=2))
PY
}

apply_model() {
  [[ -n "$MODEL" ]] || die "apply requires --model"
  ensure_openrouter_active
  require_stavrobot_dir_for_restart

  local tmp previous_model provider
  tmp=$(mktemp)
  get_current_json >"$tmp"
  previous_model=$(json_field "$tmp" model)
  provider=$(json_field "$tmp" provider)
  rm -f "$tmp"

  python3 "$ROOT_DIR/py/stavrobot_model_control.py" set-model "$CONFIG_PATH" "$MODEL" >/dev/null

  if restart_and_wait "$provider" "$MODEL" >/tmp/manage-stavrobot-model-health.json; then
    python3 - "$previous_model" "$MODEL" "$(cat /tmp/manage-stavrobot-model-health.json)" <<'PY'
import json, sys
base = json.loads(sys.argv[3])
base["previous_model"] = sys.argv[1]
base["current_model"] = sys.argv[2]
print(json.dumps(base, indent=2))
PY
    rm -f /tmp/manage-stavrobot-model-health.json
    return 0
  fi
  rm -f /tmp/manage-stavrobot-model-health.json
  return 1
}

load_profile_json() {
  python3 - "$PROFILES_PATH" "$PROFILE" <<'PY'
import json, os, sys
path, profile = sys.argv[1], sys.argv[2]
if not os.path.exists(path):
    raise SystemExit(f"profiles file not found: {path}")
payload = json.load(open(path))
profiles = payload.get("profiles", {}) if isinstance(payload, dict) else {}
if profile not in profiles:
    raise SystemExit(f"profile not found: {profile}")
print(json.dumps(profiles[profile]))
PY
}

apply_profile() {
  [[ -n "$PROFILE" ]] || die "apply-profile requires --profile"
  require_stavrobot_dir_for_restart

  local profile_json
  profile_json=$(load_profile_json)

  local expected_provider expected_model
  expected_provider=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("provider",""))' "$profile_json")
  expected_model=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("model",""))' "$profile_json")
  [[ -n "$expected_provider" && -n "$expected_model" ]] || die "profile must include provider and model"

  python3 "$ROOT_DIR/py/stavrobot_model_control.py" set-provider "$CONFIG_PATH" "$profile_json" >/dev/null

  if restart_and_wait "$expected_provider" "$expected_model"; then
    return 0
  fi
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    get-current|list-openrouter-free|apply|list-profiles|apply-profile)
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
    --profiles-path)
      PROFILES_PATH="$2"
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
    --profile)
      PROFILE="$2"
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
  list-profiles)
    list_profiles
    ;;
  apply-profile)
    apply_profile
    ;;
esac
