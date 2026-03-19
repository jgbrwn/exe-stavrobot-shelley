#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/repo.sh"
source "$ROOT_DIR/lib/prompts.sh"
source "$ROOT_DIR/lib/docker.sh"
source "$ROOT_DIR/lib/stavrobot_api.sh"
source "$ROOT_DIR/lib/summary.sh"

STAVROBOT_DIR=""
REFRESH_ONLY=0
PLUGINS_ONLY=0
CONFIG_ONLY=0
SKIP_CONFIG=0
SKIP_PLUGINS=0
SHOW_SECRETS=0
SHELLEY_STATUS_ONLY=0
SHELLEY_STATUS_JSON=0
SHELLEY_REFRESH_ONLY=0
SHELLEY_ALLOW_DIRTY=0
SHELLEY_SKIP_SMOKE=0
SHELLEY_EXPECT_DISPLAY_DATA=0
SHELLEY_REQUIRE_DISPLAY_HINTS=0
SHELLEY_EXPECT_MEDIA_REFS=0
SHELLEY_REQUIRE_MEDIA_REFS=0
SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING=0
SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS=0
SHELLEY_EXPECT_RAW_MEDIA_REJECTION=0
SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS=0
SHELLEY_BRIDGE_FIXTURE=""
SHELLEY_STRICT_RAW_MEDIA_PROFILE=0
STAVROBOT_BASE_URL="${STAVROBOT_BASE_URL:-http://localhost:8000}"

ENV_PATH=""
CONFIG_PATH=""
PLUGIN_STATE_JSON=""
OPENROUTER_OUT=""
CURRENT_JSON=""
PASSWORD_FOR_READY=""
PUBLIC_HOSTNAME_FINAL="[unchanged]"
AUTH_MODE_FINAL="apiKey"
CODER_ENABLED=false
SIGNAL_ENABLED=false
WHATSAPP_ENABLED=false
EMAIL_ENABLED=false
PLUGINS_SELECTED_COUNT=0
PLUGINS_HANDLED=0
PLUGIN_REPORT_FILE=""

usage() {
  cat <<'EOF'
Usage: ./install-stavrobot.sh --stavrobot-dir PATH [flags]

Flags:
  --stavrobot-dir PATH
  --refresh                     Pull/rebuild/restart when repo or config changed
  --plugins-only                Reuse saved plugin selections against a running stack
  --config-only                 Write .env/config only; skip pull, rebuild, and plugins
  --skip-config                 Reuse existing .env/config instead of prompting
  --skip-plugins                Skip plugin prompt/install steps
  --show-secrets
  --print-shelley-mode-status
  --json
  --refresh-shelley-mode
  --allow-dirty-shelley
  --skip-shelley-smoke
  --expect-shelley-display-data Assert persisted display_data during Shelley smoke validation
  --require-shelley-display-hints  With --expect-shelley-display-data, fail if sampled turns have no display hints
  --expect-shelley-media-refs   Assert persisted media_refs when sampled turns contain image/media hints
  --require-shelley-media-refs  With --expect-shelley-media-refs, fail if no media-ref hints are observed
  --expect-shelley-native-raw-media-gating  Assert phase-2 runtime native raw-media mapping gate in smoke
  --require-shelley-native-raw-media-hints  With --expect-shelley-native-raw-media-gating, fail if no raw-inline hints are observed
  --expect-shelley-raw-media-rejection  Assert runtime rejection behavior for invalid raw-inline artifacts in smoke
  --require-shelley-raw-media-rejection-hints  With --expect-shelley-raw-media-rejection, fail if no invalid raw-inline hints are observed
  --shelley-bridge-fixture NAME  Optional test fixture mode for Shelley smoke bridge payloads
  --strict-shelley-raw-media-profile  Run authoritative strict managed raw-media proof profile during Shelley refresh
  --help

Environment:
  STAVROBOT_BASE_URL   Local Stavrobot URL for readiness/plugin calls (default: http://localhost:8000)

Shelley mode helpers:
  --print-shelley-mode-status   Read-only managed Shelley mode status
  --json                        With --print-shelley-mode-status, emit machine-readable JSON
  --refresh-shelley-mode        Apply/rebuild/smoke managed Shelley mode in /opt/shelley
  --allow-dirty-shelley         Allow managed Shelley refresh against a dirty checkout
  --skip-shelley-smoke          Skip isolated Shelley smoke validation during refresh
  --expect-shelley-display-data Assert persisted display_data during Shelley smoke validation
  --require-shelley-display-hints  With --expect-shelley-display-data, fail if sampled turns have no display hints
  --expect-shelley-media-refs   Assert persisted media_refs when sampled turns contain image/media hints
  --require-shelley-media-refs  With --expect-shelley-media-refs, fail if no media-ref hints are observed
  --expect-shelley-native-raw-media-gating  Assert phase-2 runtime native raw-media mapping gate in smoke
  --require-shelley-native-raw-media-hints  With --expect-shelley-native-raw-media-gating, fail if no raw-inline hints are observed
  --expect-shelley-raw-media-rejection  Assert runtime rejection behavior for invalid raw-inline artifacts in smoke
  --require-shelley-raw-media-rejection-hints  With --expect-shelley-raw-media-rejection, fail if no invalid raw-inline hints are observed
  --shelley-bridge-fixture NAME  Optional test fixture mode for Shelley smoke bridge payloads
  --strict-shelley-raw-media-profile  Run authoritative strict managed raw-media proof profile during Shelley refresh
EOF
}

json_quote() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

append_plugin_report() {
  local line="$1"
  printf '%s\n' "$line" >> "$PLUGIN_REPORT_FILE"
}

render_current_state() {
  CURRENT_JSON="$ROOT_DIR/state/current-config.json"
  python3 "$ROOT_DIR/py/load_current_config.py" \
    "$STAVROBOT_DIR/env.example" \
    "$ENV_PATH" \
    "$STAVROBOT_DIR/config.example.toml" \
    "$CONFIG_PATH" > "$CURRENT_JSON"
  ensure_private_file "$CURRENT_JSON"
}

fetch_openrouter_suggestions() {
  OPENROUTER_OUT="$ROOT_DIR/state/openrouter-free-models.json"
  if python3 "$ROOT_DIR/py/openrouter_models.py" > "$OPENROUTER_OUT"; then
    ensure_private_file "$OPENROUTER_OUT"
    info "Fetched OpenRouter free model suggestions into $OPENROUTER_OUT"
    return 0
  fi
  warn "Failed to fetch OpenRouter free model suggestions"
  return 1
}

prompt_openrouter_model() {
  local current_model="$1"
  local default_model="${current_model:-openrouter/free}"
  local openrouter_catalog="${OPENROUTER_OUT:-$ROOT_DIR/state/openrouter-free-models.json}"
  local -a model_choices=()

  if [[ -f "$openrouter_catalog" ]]; then
    mapfile -t model_choices < <(python3 - "$openrouter_catalog" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    raise SystemExit(0)
for item in data.get('models', [])[:12]:
    model_id = item.get('id', '').strip()
    if model_id:
        print(model_id)
PY
)
  fi

  if (( ${#model_choices[@]} > 0 )); then
    printf '[info] OpenRouter free-model choices are from the current live catalog\n' >&2
    selection=$(prompt_choice "OpenRouter model:" "${model_choices[@]}" "Manual entry")
    if [[ "$selection" == "Manual entry" ]]; then
      selection=$(prompt_text "OpenRouter model ID" "$default_model")
    fi
  else
    selection=$(prompt_text "OpenRouter model ID" "$default_model")
  fi

  selection=${selection:-$default_model}
  [[ -n "$selection" ]] || die "OpenRouter model ID is required"
  printf '%s\n' "$selection"
}

load_runtime_password() {
  if [[ -f "$ROOT_DIR/state/render-config.json" ]]; then
    PASSWORD_FOR_READY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("password", ""))' "$ROOT_DIR/state/render-config.json" 2>/dev/null || true)
  elif [[ -f "$CONFIG_PATH" ]]; then
    PASSWORD_FOR_READY=$(python3 - "$CONFIG_PATH" <<'PY'
import sys, tomllib
try:
    data = tomllib.loads(open(sys.argv[1]).read())
    print(data.get('password', ''))
except Exception:
    print('')
PY
)
  fi
}

load_runtime_metadata() {
  if [[ -f "$CONFIG_PATH" ]]; then
    eval "$(python3 - "$CONFIG_PATH" <<'PY'
import sys, tomllib
try:
    data = tomllib.loads(open(sys.argv[1]).read())
except Exception:
    data = {}
password = data.get('password', '')
public_hostname = data.get('publicHostname', '[unchanged]')
auth_mode = 'apiKey' if data.get('apiKey') else ('authFile' if data.get('authFile') else 'unknown')
coder_enabled = 'true' if data.get('coder') else 'false'
signal_enabled = 'true' if data.get('signal') else 'false'
whatsapp_enabled = 'true' if data.get('whatsapp') else 'false'
email_enabled = 'true' if data.get('email') else 'false'
print(f'PASSWORD_FOR_READY={password!r}')
print(f'PUBLIC_HOSTNAME_FINAL={public_hostname!r}')
print(f'AUTH_MODE_FINAL={auth_mode!r}')
print(f'CODER_ENABLED={coder_enabled!r}')
print(f'SIGNAL_ENABLED={signal_enabled!r}')
print(f'WHATSAPP_ENABLED={whatsapp_enabled!r}')
print(f'EMAIL_ENABLED={email_enabled!r}')
PY
)"
  fi
}

wait_for_stavrobot_ready() {
  local local_base_url="$STAVROBOT_BASE_URL"
  [[ -n "$PASSWORD_FOR_READY" ]] || die "Could not determine Stavrobot password for readiness checks"
  if wait_for_http_basic_auth "$local_base_url/" "$PASSWORD_FOR_READY" 120; then
    info "Stavrobot is responding at $local_base_url"
    if stavrobot_list_plugins "$local_base_url" "$PASSWORD_FOR_READY" >/dev/null 2>&1; then
      info "Plugin settings endpoint is reachable"
    else
      warn "Plugin settings endpoint check failed"
    fi
  else
    die "Stavrobot did not become ready within timeout"
  fi
}

run_plugins_from_state() {
  local local_base_url="$STAVROBOT_BASE_URL"
  [[ -f "$PLUGIN_STATE_JSON" ]] || return 0
  [[ -n "$PASSWORD_FOR_READY" ]] || die "Missing password for plugin installation"
  while IFS= read -r plugin_entry; do
    [[ -n "$plugin_entry" ]] || continue
    plugin_name=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["name"])' "$plugin_entry")
    plugin_repo=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["repo_url"])' "$plugin_entry")
    plugin_config=$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["config"]))' "$plugin_entry")
    info "Installing plugin $plugin_name"
    install_response=$(stavrobot_install_plugin "$local_base_url" "$PASSWORD_FOR_READY" "$plugin_repo" || true)
    install_status=$(printf '%s' "$install_response" | python3 -c 'import json,sys; data=json.load(sys.stdin); print("already installed" if "already installed" in str(data.get("error","")) else ("ok" if "error" not in data else "error"))')
    if [[ "$install_status" == "error" ]]; then
      printf '%s\n' "$install_response" >&2
      append_plugin_report "$plugin_name: install failed"
      die "Failed to install plugin $plugin_name"
    fi
    if [[ "$install_status" == "already installed" ]]; then
      append_plugin_report "$plugin_name: already installed"
    else
      append_plugin_report "$plugin_name: installed"
    fi
    if [[ "$plugin_config" != "{}" ]]; then
      info "Configuring plugin $plugin_name"
      configure_response=$(stavrobot_configure_plugin "$local_base_url" "$PASSWORD_FOR_READY" "$plugin_name" "$plugin_config" || true)
      if ! printf '%s' "$configure_response" | python3 -c 'import json,sys; data=json.load(sys.stdin); import sys as s; s.exit(0 if "error" not in data else 1)'; then
        printf '%s\n' "$configure_response" >&2
        append_plugin_report "$plugin_name: configure failed"
        die "Failed to configure plugin $plugin_name"
      fi
      warnings=$(printf '%s' "$configure_response" | python3 -c 'import json,sys; data=json.load(sys.stdin); print("; ".join(data.get("warnings", [])))')
      if [[ -n "$warnings" ]]; then
        append_plugin_report "$plugin_name: configured with warnings: $warnings"
      else
        append_plugin_report "$plugin_name: configured"
      fi
    fi
    ((PLUGINS_HANDLED+=1))
  done < <(python3 -c 'import json,sys; [print(json.dumps(x)) for x in json.load(open(sys.argv[1])).get("plugins", [])]' "$PLUGIN_STATE_JSON")
}

prompt_plugin_selection() {
  local plugin_tmp="$ROOT_DIR/state/plugin-selections.jsonl"
  : > "$plugin_tmp"
  while IFS= read -r plugin_json; do
    name=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["name"])' "$plugin_json")
    description=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["description"])' "$plugin_json")
    repo_url=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["repo_url"])' "$plugin_json")
    default_yes=$(python3 -c 'import json,sys; print("Y" if json.loads(sys.argv[1]).get("enabled_by_default") else "N")' "$plugin_json")
    if prompt_yes_no "Install plugin '$name' ($description)?" "$default_yes"; then
      ((PLUGINS_SELECTED_COUNT+=1))
      config_json='{}'
      while IFS= read -r field_json; do
        [[ -n "$field_json" ]] || continue
        field_key=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["key"])' "$field_json")
        field_prompt=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["prompt"])' "$field_json")
        field_secret=$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("secret") else "0")' "$field_json")
        field_default=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("default", ""))' "$field_json")
        if [[ "$field_secret" == "1" ]]; then
          field_value=$(prompt_secret "$field_prompt" "$field_default")
        else
          field_value=$(prompt_text "$field_prompt" "$field_default")
        fi
        field_value=${field_value:-$field_default}
        [[ -n "$field_value" ]] || die "Plugin '$name' requires '$field_key'"
        config_json=$(python3 - "$config_json" "$field_key" "$field_value" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
obj[sys.argv[2]] = sys.argv[3]
print(json.dumps(obj))
PY
)
      done < <(python3 -c 'import json,sys; plugin=json.loads(sys.argv[1]); [print(json.dumps(x)) for x in plugin.get("required_config", [])]' "$plugin_json")

      while IFS= read -r field_json; do
        [[ -n "$field_json" ]] || continue
        field_key=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["key"])' "$field_json")
        field_prompt=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["prompt"])' "$field_json")
        field_secret=$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("secret") else "0")' "$field_json")
        field_default=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("default", ""))' "$field_json")
        if [[ "$field_secret" == "1" ]]; then
          field_value=$(prompt_secret "$field_prompt (optional; press Enter to keep default)" "$field_default")
        else
          field_value=$(prompt_optional_text "$field_prompt (optional; type SKIP to omit)" "$field_default")
        fi
        if [[ "$field_value" == "__SKIP__" ]]; then
          continue
        fi
        field_value=${field_value:-$field_default}
        if [[ -n "$field_value" ]]; then
          config_json=$(python3 - "$config_json" "$field_key" "$field_value" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
obj[sys.argv[2]] = sys.argv[3]
print(json.dumps(obj))
PY
)
        fi
      done < <(python3 -c 'import json,sys; plugin=json.loads(sys.argv[1]); [print(json.dumps(x)) for x in plugin.get("optional_config", [])]' "$plugin_json")

      python3 - "$name" "$repo_url" "$config_json" >> "$plugin_tmp" <<'PY'
import json, sys
print(json.dumps({"name": sys.argv[1], "repo_url": sys.argv[2], "config": json.loads(sys.argv[3])}))
PY
    fi
  done < <(python3 -c 'import json,sys; [print(json.dumps(x)) for x in json.load(open(sys.argv[1]))]' "$ROOT_DIR/data/plugin-catalog.json")

  python3 - "$plugin_tmp" > "$PLUGIN_STATE_JSON" <<'PY'
import json, sys
entries = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line:
            entries.append(json.loads(line))
print(json.dumps({"plugins": entries}, indent=2))
PY
  ensure_private_file "$PLUGIN_STATE_JSON"
  rm -f "$plugin_tmp"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stavrobot-dir)
      STAVROBOT_DIR="$2"
      shift 2
      ;;
    --refresh)
      REFRESH_ONLY=1
      shift
      ;;
    --plugins-only)
      PLUGINS_ONLY=1
      shift
      ;;
    --config-only)
      CONFIG_ONLY=1
      shift
      ;;
    --skip-config)
      SKIP_CONFIG=1
      shift
      ;;
    --skip-plugins)
      SKIP_PLUGINS=1
      shift
      ;;
    --show-secrets)
      SHOW_SECRETS=1
      shift
      ;;
    --print-shelley-mode-status)
      SHELLEY_STATUS_ONLY=1
      shift
      ;;
    --json)
      SHELLEY_STATUS_JSON=1
      shift
      ;;
    --refresh-shelley-mode)
      SHELLEY_REFRESH_ONLY=1
      shift
      ;;
    --allow-dirty-shelley)
      SHELLEY_ALLOW_DIRTY=1
      shift
      ;;
    --skip-shelley-smoke)
      SHELLEY_SKIP_SMOKE=1
      shift
      ;;
    --expect-shelley-display-data)
      SHELLEY_EXPECT_DISPLAY_DATA=1
      shift
      ;;
    --require-shelley-display-hints)
      SHELLEY_REQUIRE_DISPLAY_HINTS=1
      shift
      ;;
    --expect-shelley-media-refs)
      SHELLEY_EXPECT_MEDIA_REFS=1
      shift
      ;;
    --require-shelley-media-refs)
      SHELLEY_REQUIRE_MEDIA_REFS=1
      shift
      ;;
    --expect-shelley-native-raw-media-gating)
      SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING=1
      shift
      ;;
    --require-shelley-native-raw-media-hints)
      SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS=1
      shift
      ;;
    --expect-shelley-raw-media-rejection)
      SHELLEY_EXPECT_RAW_MEDIA_REJECTION=1
      shift
      ;;
    --require-shelley-raw-media-rejection-hints)
      SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS=1
      shift
      ;;
    --shelley-bridge-fixture)
      SHELLEY_BRIDGE_FIXTURE="$2"
      shift 2
      ;;
    --strict-shelley-raw-media-profile)
      SHELLEY_STRICT_RAW_MEDIA_PROFILE=1
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

if (( SHELLEY_REFRESH_ONLY )) && (( SHELLEY_STATUS_JSON )); then
  die "--json cannot be combined with --refresh-shelley-mode"
fi

if (( SHELLEY_STATUS_ONLY )); then
  (( SHELLEY_REFRESH_ONLY == 0 )) || die "--print-shelley-mode-status cannot be combined with --refresh-shelley-mode"
  [[ -z "$STAVROBOT_DIR" ]] || die "--print-shelley-mode-status cannot be combined with --stavrobot-dir"
  (( REFRESH_ONLY == 0 && PLUGINS_ONLY == 0 && CONFIG_ONLY == 0 && SKIP_CONFIG == 0 && SKIP_PLUGINS == 0 && SHOW_SECRETS == 0 )) || \
    die "--print-shelley-mode-status cannot be combined with normal installer mutation flags"
  (( SHELLEY_ALLOW_DIRTY == 0 && SHELLEY_SKIP_SMOKE == 0 && SHELLEY_EXPECT_DISPLAY_DATA == 0 && SHELLEY_REQUIRE_DISPLAY_HINTS == 0 && SHELLEY_EXPECT_MEDIA_REFS == 0 && SHELLEY_REQUIRE_MEDIA_REFS == 0 && SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING == 0 && SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS == 0 && SHELLEY_EXPECT_RAW_MEDIA_REJECTION == 0 && SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS == 0 && SHELLEY_STRICT_RAW_MEDIA_PROFILE == 0 )) && [[ -z "$SHELLEY_BRIDGE_FIXTURE" ]] || \
    die "--print-shelley-mode-status cannot be combined with Shelley refresh-only flags"
else
  (( SHELLEY_STATUS_JSON == 0 )) || die "--json currently requires --print-shelley-mode-status"
fi

if (( SHELLEY_REFRESH_ONLY )); then
  [[ -z "$STAVROBOT_DIR" ]] || die "--refresh-shelley-mode cannot be combined with --stavrobot-dir"
  (( REFRESH_ONLY == 0 && PLUGINS_ONLY == 0 && CONFIG_ONLY == 0 && SKIP_CONFIG == 0 && SKIP_PLUGINS == 0 && SHOW_SECRETS == 0 )) || \
    die "--refresh-shelley-mode cannot be combined with normal installer mutation flags"
fi

if (( (SHELLEY_ALLOW_DIRTY || SHELLEY_SKIP_SMOKE || SHELLEY_EXPECT_DISPLAY_DATA || SHELLEY_REQUIRE_DISPLAY_HINTS || SHELLEY_EXPECT_MEDIA_REFS || SHELLEY_REQUIRE_MEDIA_REFS || SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING || SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS || SHELLEY_EXPECT_RAW_MEDIA_REJECTION || SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS || SHELLEY_STRICT_RAW_MEDIA_PROFILE) && SHELLEY_REFRESH_ONLY == 0 )) || ([[ -n "$SHELLEY_BRIDGE_FIXTURE" ]] && (( SHELLEY_REFRESH_ONLY == 0 ))); then
  die "--allow-dirty-shelley, --skip-shelley-smoke, --expect-shelley-display-data, --require-shelley-display-hints, --expect-shelley-media-refs, --require-shelley-media-refs, --expect-shelley-native-raw-media-gating, --require-shelley-native-raw-media-hints, --expect-shelley-raw-media-rejection, --require-shelley-raw-media-rejection-hints, --strict-shelley-raw-media-profile, and --shelley-bridge-fixture require --refresh-shelley-mode"
fi
if (( SHELLEY_REQUIRE_DISPLAY_HINTS == 1 && SHELLEY_EXPECT_DISPLAY_DATA == 0 )); then
  die "--require-shelley-display-hints requires --expect-shelley-display-data"
fi
if (( SHELLEY_REQUIRE_MEDIA_REFS == 1 && SHELLEY_EXPECT_MEDIA_REFS == 0 )); then
  die "--require-shelley-media-refs requires --expect-shelley-media-refs"
fi
if (( SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS == 1 && SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING == 0 )); then
  die "--require-shelley-native-raw-media-hints requires --expect-shelley-native-raw-media-gating"
fi
if (( SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS == 1 && SHELLEY_EXPECT_RAW_MEDIA_REJECTION == 0 )); then
  die "--require-shelley-raw-media-rejection-hints requires --expect-shelley-raw-media-rejection"
fi
if (( SHELLEY_STRICT_RAW_MEDIA_PROFILE == 1 )); then
  if (( SHELLEY_EXPECT_DISPLAY_DATA == 1 || SHELLEY_REQUIRE_DISPLAY_HINTS == 1 || SHELLEY_EXPECT_MEDIA_REFS == 1 || SHELLEY_REQUIRE_MEDIA_REFS == 1 || SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING == 1 || SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS == 1 || SHELLEY_EXPECT_RAW_MEDIA_REJECTION == 1 || SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS == 1 )) || [[ -n "$SHELLEY_BRIDGE_FIXTURE" ]]; then
    die "--strict-shelley-raw-media-profile cannot be combined with explicit --expect/--require Shelley smoke flags or --shelley-bridge-fixture"
  fi
fi

if (( SHELLEY_STATUS_ONLY )); then
  status_args=()
  if (( SHELLEY_STATUS_JSON )); then
    status_args+=(--json)
  fi
  exec "$ROOT_DIR/print-shelley-managed-status.sh" "${status_args[@]}"
fi

if (( SHELLEY_REFRESH_ONLY )); then
  refresh_args=(--shelley-dir /opt/shelley --profile-state-path /var/lib/stavrobot-installer/shelley-bridge-profiles.json)
  if (( SHELLEY_ALLOW_DIRTY )); then
    refresh_args+=(--allow-dirty)
  fi
  if (( SHELLEY_SKIP_SMOKE )); then
    refresh_args+=(--skip-smoke)
  fi
  if (( SHELLEY_EXPECT_DISPLAY_DATA )); then
    refresh_args+=(--smoke-expect-display-data)
  fi
  if (( SHELLEY_REQUIRE_DISPLAY_HINTS )); then
    refresh_args+=(--smoke-require-display-hints)
  fi
  if (( SHELLEY_EXPECT_MEDIA_REFS )); then
    refresh_args+=(--smoke-expect-media-refs)
  fi
  if (( SHELLEY_REQUIRE_MEDIA_REFS )); then
    refresh_args+=(--smoke-require-media-refs)
  fi
  if (( SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING )); then
    refresh_args+=(--smoke-expect-native-raw-media-gating)
  fi
  if (( SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS )); then
    refresh_args+=(--smoke-require-native-raw-media-hints)
  fi
  if (( SHELLEY_EXPECT_RAW_MEDIA_REJECTION )); then
    refresh_args+=(--smoke-expect-raw-media-rejection)
  fi
  if (( SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS )); then
    refresh_args+=(--smoke-require-raw-media-rejection-hints)
  fi
  if [[ -n "$SHELLEY_BRIDGE_FIXTURE" ]]; then
    refresh_args+=(--smoke-bridge-fixture "$SHELLEY_BRIDGE_FIXTURE")
  fi
  if (( SHELLEY_STRICT_RAW_MEDIA_PROFILE )); then
    refresh_args+=(--smoke-strict-raw-media-profile)
  fi
  exec "$ROOT_DIR/refresh-shelley-managed-s1.sh" "${refresh_args[@]}"
fi

[[ -n "$STAVROBOT_DIR" ]] || die "--stavrobot-dir is required"

require_cmd git
require_cmd python3
require_cmd docker
require_cmd curl

validate_stavrobot_repo "$STAVROBOT_DIR"
mkdir -p "$ROOT_DIR/state"
ENV_PATH="$STAVROBOT_DIR/.env"
CONFIG_PATH="$STAVROBOT_DIR/data/main/config.toml"
PLUGIN_STATE_JSON="$ROOT_DIR/state/last-plugin-inputs.json"
PLUGIN_REPORT_FILE="$ROOT_DIR/state/last-plugin-report.txt"
: > "$PLUGIN_REPORT_FILE"
mkdir -p "$(dirname "$CONFIG_PATH")"

info "Documented plan: $ROOT_DIR/IMPLEMENTATION_PLAN.md"
info "Validating upstream stavrobot repo"
BEFORE_HEAD=$(get_repo_head "$STAVROBOT_DIR")
if (( CONFIG_ONLY || SKIP_CONFIG )); then
  AFTER_HEAD="$BEFORE_HEAD"
  info "Config-only path: skipping upstream stavrobot pull"
else
  check_repo_clean_for_pull "$STAVROBOT_DIR"
  pull_latest_stavrobot "$STAVROBOT_DIR"
  AFTER_HEAD=$(get_repo_head "$STAVROBOT_DIR")

  if [[ "$BEFORE_HEAD" != "$AFTER_HEAD" ]]; then
    info "Updated stavrobot from $BEFORE_HEAD to $AFTER_HEAD"
  else
    info "Stavrobot already up to date at $AFTER_HEAD"
  fi
fi

if (( !PLUGINS_ONLY )) && [[ -z "${SHELLEY_INSTALLER_TEST_SKIP_OPENROUTER_FETCH:-}" ]]; then
  fetch_openrouter_suggestions || true
fi

if (( PLUGINS_ONLY )); then
  load_runtime_metadata
  [[ -f "$PLUGIN_STATE_JSON" ]] || die "No saved plugin state at $PLUGIN_STATE_JSON"
  wait_for_stavrobot_ready
  run_plugins_from_state
  print_run_summary "$BEFORE_HEAD" "$AFTER_HEAD" false false 0 "$PLUGINS_HANDLED" "$PLUGIN_REPORT_FILE"
  print_next_steps "$PUBLIC_HOSTNAME_FINAL" "$CODER_ENABLED" "$SIGNAL_ENABLED" "$WHATSAPP_ENABLED" "$EMAIL_ENABLED" "$AUTH_MODE_FINAL"
  exit 0
fi

BEFORE_ENV_HASH=$(sha256_file "$ENV_PATH")
BEFORE_CONFIG_HASH=$(sha256_file "$CONFIG_PATH")

if (( REFRESH_ONLY )); then
  info "Refresh mode: skipping config prompts"
  load_runtime_metadata
elif (( SKIP_CONFIG )); then
  info "Skip-config mode: reusing existing config files"
  load_runtime_metadata
else
  render_current_state

  ENV_EXAMPLE_TZ=$(json_get "$CURRENT_JSON" env_example.TZ)
  ENV_CURRENT_TZ=$(json_get "$CURRENT_JSON" env_current.TZ)
  TZ_DEFAULT=${ENV_CURRENT_TZ:-$ENV_EXAMPLE_TZ}
  TZ_VALUE=$(prompt_text "Timezone" "$TZ_DEFAULT")
  TZ_VALUE=${TZ_VALUE:-$TZ_DEFAULT}

  if prompt_yes_no "Review advanced Postgres env overrides?" "N"; then
    PG_USER_DEFAULT=$(json_get "$CURRENT_JSON" env_current.POSTGRES_USER)
    PG_USER_DEFAULT=${PG_USER_DEFAULT:-$(json_get "$CURRENT_JSON" env_example.POSTGRES_USER)}
    PG_USER=$(prompt_text "Postgres username" "$PG_USER_DEFAULT")
    PG_USER=${PG_USER:-$PG_USER_DEFAULT}

    PG_PASSWORD_DEFAULT=$(json_get "$CURRENT_JSON" env_current.POSTGRES_PASSWORD)
    PG_PASSWORD_DEFAULT=${PG_PASSWORD_DEFAULT:-$(json_get "$CURRENT_JSON" env_example.POSTGRES_PASSWORD)}
    if (( SHOW_SECRETS )); then
      PG_PASSWORD=$(prompt_secret "Postgres password" "$PG_PASSWORD_DEFAULT")
    else
      PG_PASSWORD=$(prompt_secret "Postgres password" "$(mask_secret "$PG_PASSWORD_DEFAULT")")
    fi
    PG_PASSWORD=${PG_PASSWORD:-$PG_PASSWORD_DEFAULT}

    PG_DB_DEFAULT=$(json_get "$CURRENT_JSON" env_current.POSTGRES_DB)
    PG_DB_DEFAULT=${PG_DB_DEFAULT:-$(json_get "$CURRENT_JSON" env_example.POSTGRES_DB)}
    PG_DB=$(prompt_text "Postgres database name" "$PG_DB_DEFAULT")
    PG_DB=${PG_DB:-$PG_DB_DEFAULT}
  else
    PG_USER=$(json_get "$CURRENT_JSON" env_example.POSTGRES_USER)
    PG_PASSWORD=$(json_get "$CURRENT_JSON" env_example.POSTGRES_PASSWORD)
    PG_DB=$(json_get "$CURRENT_JSON" env_example.POSTGRES_DB)
  fi

  PROVIDER_MODE=$(prompt_choice "Provider setup:" "Anthropic" "OpenRouter" "OpenAI-compatible" "Manual/custom")

  PROVIDER=""
  MODEL=""
  API_KEY=""
  AUTH_FILE=""
  OWNER_NAME_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.name)
  OWNER_NAME_DEFAULT=${OWNER_NAME_DEFAULT:-$(json_get "$CURRENT_JSON" toml_example.owner.name)}

  case "$PROVIDER_MODE" in
    Anthropic)
      PROVIDER="anthropic"
      AUTH_MODE=$(prompt_choice "Anthropic auth mode:" "API key" "authFile")
      AUTH_MODE_FINAL=$([[ "$AUTH_MODE" == "API key" ]] && echo apiKey || echo authFile)
      MODEL_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.model)
      MODEL_DEFAULT=${MODEL_DEFAULT:-$(json_get "$CURRENT_JSON" toml_example.model)}
      MODEL=$(prompt_text "Anthropic model" "$MODEL_DEFAULT")
      MODEL=${MODEL:-$MODEL_DEFAULT}
      if [[ "$AUTH_MODE" == "API key" ]]; then
        API_KEY_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.apiKey)
        if (( SHOW_SECRETS )); then
          API_KEY=$(prompt_secret "Anthropic API key" "$API_KEY_DEFAULT")
        else
          API_KEY=$(prompt_secret "Anthropic API key" "$(mask_secret "$API_KEY_DEFAULT")")
        fi
        API_KEY=${API_KEY:-$API_KEY_DEFAULT}
        [[ -n "$API_KEY" ]] || die "Anthropic API key is required when using API key auth"
      else
        AUTH_FILE_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.authFile)
        AUTH_FILE_DEFAULT=${AUTH_FILE_DEFAULT:-/app/data/auth.json}
        AUTH_FILE=$(prompt_text "Auth file path" "$AUTH_FILE_DEFAULT")
        AUTH_FILE=${AUTH_FILE:-$AUTH_FILE_DEFAULT}
        [[ -n "$AUTH_FILE" ]] || die "authFile path is required when using authFile auth"
      fi
      ;;
    OpenRouter)
      PROVIDER="openrouter"
      AUTH_MODE=$(prompt_choice "OpenRouter auth mode:" "API key" "authFile")
      AUTH_MODE_FINAL=$([[ "$AUTH_MODE" == "API key" ]] && echo apiKey || echo authFile)
      MODEL_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.model)
      if [[ "$(json_get "$CURRENT_JSON" toml_current.provider)" != "openrouter" ]]; then
        MODEL_DEFAULT="openrouter/free"
      fi
      MODEL=$(prompt_openrouter_model "$MODEL_DEFAULT")
      if [[ "$AUTH_MODE" == "API key" ]]; then
        API_KEY_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.apiKey)
        if (( SHOW_SECRETS )); then
          API_KEY=$(prompt_secret "OpenRouter API key" "$API_KEY_DEFAULT")
        else
          API_KEY=$(prompt_secret "OpenRouter API key" "$(mask_secret "$API_KEY_DEFAULT")")
        fi
        API_KEY=${API_KEY:-$API_KEY_DEFAULT}
        [[ -n "$API_KEY" ]] || die "OpenRouter API key is required when using API key auth"
      else
        AUTH_FILE_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.authFile)
        AUTH_FILE_DEFAULT=${AUTH_FILE_DEFAULT:-/app/data/auth.json}
        AUTH_FILE=$(prompt_text "OpenRouter auth file path" "$AUTH_FILE_DEFAULT")
        AUTH_FILE=${AUTH_FILE:-$AUTH_FILE_DEFAULT}
        [[ -n "$AUTH_FILE" ]] || die "OpenRouter authFile path is required when using authFile auth"
      fi
      ;;
    OpenAI-compatible)
      warn "Current upstream stavrobot config exposes provider and model, but no explicit base URL field. Arbitrary OpenAI-compatible setups may require upstream support beyond this installer."
      AUTH_MODE_FINAL=apiKey
      PROVIDER_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.provider)
      PROVIDER=$(prompt_text "Provider label" "$PROVIDER_DEFAULT")
      MODEL=$(prompt_text "Model ID" "")
      API_KEY=$(prompt_secret "API key" "")
      [[ -n "$PROVIDER" ]] || die "Provider label is required"
      [[ -n "$MODEL" ]] || die "Model ID is required"
      [[ -n "$API_KEY" ]] || die "API key is required"
      ;;
    Manual/custom)
      PROVIDER_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.provider)
      PROVIDER=$(prompt_text "Provider label" "$PROVIDER_DEFAULT")
      MODEL_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.model)
      MODEL=$(prompt_text "Model ID" "$MODEL_DEFAULT")
      MODEL=${MODEL:-$MODEL_DEFAULT}
      API_KEY=$(prompt_secret "API key (or leave blank to use authFile)" "")
      if [[ -z "$API_KEY" ]]; then
        AUTH_FILE_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.authFile)
        AUTH_FILE=$(prompt_text "Auth file path" "$AUTH_FILE_DEFAULT")
        AUTH_FILE=${AUTH_FILE:-$AUTH_FILE_DEFAULT}
        AUTH_MODE_FINAL=authFile
      else
        AUTH_MODE_FINAL=apiKey
      fi
      [[ -n "$PROVIDER" ]] || die "Provider label is required"
      [[ -n "$MODEL" ]] || die "Model ID is required"
      [[ -n "$API_KEY" || -n "$AUTH_FILE" ]] || die "Either API key or authFile is required"
      ;;
  esac

  PASSWORD_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.password)
  PASSWORD_DEFAULT=${PASSWORD_DEFAULT:-change-me}
  if (( SHOW_SECRETS )); then
    PASSWORD=$(prompt_secret "HTTP basic auth password" "$PASSWORD_DEFAULT")
  else
    PASSWORD=$(prompt_secret "HTTP basic auth password" "$(mask_secret "$PASSWORD_DEFAULT")")
  fi
  PASSWORD=${PASSWORD:-$PASSWORD_DEFAULT}

  PUBLIC_HOSTNAME_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.publicHostname)
  PUBLIC_HOSTNAME_DEFAULT=${PUBLIC_HOSTNAME_DEFAULT:-https://example.com}
  PUBLIC_HOSTNAME=$(prompt_text "Public HTTPS URL" "$PUBLIC_HOSTNAME_DEFAULT")
  PUBLIC_HOSTNAME=${PUBLIC_HOSTNAME:-$PUBLIC_HOSTNAME_DEFAULT}
  PUBLIC_HOSTNAME=${PUBLIC_HOSTNAME%/}
  [[ "$PUBLIC_HOSTNAME" =~ ^https?:// ]] || die "publicHostname must start with http:// or https://"
  PUBLIC_HOSTNAME_FINAL="$PUBLIC_HOSTNAME"

  OWNER_NAME=$(prompt_text "Owner name" "$OWNER_NAME_DEFAULT")
  OWNER_NAME=${OWNER_NAME:-$OWNER_NAME_DEFAULT}
  [[ -n "$OWNER_NAME" ]] || die "Owner name is required by stavrobot"

  OWNER_SIGNAL_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.signal)
  OWNER_SIGNAL=$(prompt_optional_text "Owner Signal number (optional; type SKIP to omit)" "$OWNER_SIGNAL_DEFAULT")
  [[ "$OWNER_SIGNAL" == "__SKIP__" ]] && OWNER_SIGNAL=""
  OWNER_SIGNAL=${OWNER_SIGNAL:-$OWNER_SIGNAL_DEFAULT}

  OWNER_TELEGRAM_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.telegram)
  OWNER_TELEGRAM=$(prompt_optional_text "Owner Telegram chat ID (optional; type SKIP to omit)" "$OWNER_TELEGRAM_DEFAULT")
  [[ "$OWNER_TELEGRAM" == "__SKIP__" ]] && OWNER_TELEGRAM=""
  OWNER_TELEGRAM=${OWNER_TELEGRAM:-$OWNER_TELEGRAM_DEFAULT}

  OWNER_WHATSAPP_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.whatsapp)
  OWNER_WHATSAPP=$(prompt_optional_text "Owner WhatsApp number (optional; type SKIP to omit)" "$OWNER_WHATSAPP_DEFAULT")
  [[ "$OWNER_WHATSAPP" == "__SKIP__" ]] && OWNER_WHATSAPP=""
  OWNER_WHATSAPP=${OWNER_WHATSAPP:-$OWNER_WHATSAPP_DEFAULT}

  OWNER_EMAIL_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.email)
  OWNER_EMAIL=$(prompt_optional_text "Owner email address (optional; type SKIP to omit)" "$OWNER_EMAIL_DEFAULT")
  [[ "$OWNER_EMAIL" == "__SKIP__" ]] && OWNER_EMAIL=""
  OWNER_EMAIL=${OWNER_EMAIL:-$OWNER_EMAIL_DEFAULT}

  TELEGRAM_BOT_TOKEN=""
  if prompt_yes_no "Enable Telegram integration?" "N"; then
    TELEGRAM_BOT_TOKEN=$(prompt_secret "Telegram bot token" "")
  fi

  SIGNAL_ACCOUNT=""
  COMPOSE_PROFILES=""
  if prompt_yes_no "Enable Signal integration?" "N"; then
    SIGNAL_ENABLED=true
    COMPOSE_PROFILES="signal"
    SIGNAL_ACCOUNT=$(prompt_text "Signal bot account number" "")
  fi

  if prompt_yes_no "Enable WhatsApp integration?" "N"; then
    WHATSAPP_ENABLED=true
  fi

  WEBHOOK_SECRET=""
  SMTP_HOST=""
  SMTP_PORT=""
  SMTP_USER=""
  SMTP_PASSWORD=""
  FROM_ADDRESS=""
  if prompt_yes_no "Enable email integration?" "N"; then
    EMAIL_ENABLED=true
    WEBHOOK_SECRET=$(prompt_secret "Email webhook secret" "")
    SMTP_HOST=$(prompt_optional_text "SMTP host (optional; type SKIP to omit)" "")
    [[ "$SMTP_HOST" == "__SKIP__" ]] && SMTP_HOST=""
    SMTP_PORT=$(prompt_optional_text "SMTP port (optional; type SKIP to omit)" "587")
    [[ "$SMTP_PORT" == "__SKIP__" ]] && SMTP_PORT=""
    SMTP_USER=$(prompt_optional_text "SMTP username (optional; type SKIP to omit)" "")
    [[ "$SMTP_USER" == "__SKIP__" ]] && SMTP_USER=""
    SMTP_PASSWORD=$(prompt_secret "SMTP password (optional; press Enter to omit)" "")
    FROM_ADDRESS=$(prompt_optional_text "From address (optional; type SKIP to omit)" "")
    [[ "$FROM_ADDRESS" == "__SKIP__" ]] && FROM_ADDRESS=""
  fi

  CODER_MODEL=""
  if prompt_yes_no "Enable coder container?" "N"; then
    CODER_ENABLED=true
    CODER_MODEL=$(prompt_choice "Coder model:" "sonnet" "opus" "haiku")
  fi

  CUSTOM_PROMPT=""
  if prompt_yes_no "Configure custom prompt?" "N"; then
    CUSTOM_PROMPT=$(prompt_multiline "Enter custom prompt")
  fi

  ENV_JSON="$ROOT_DIR/state/render-env.json"
  cat > "$ENV_JSON" <<EOF
{
  "TZ": $(json_quote "$TZ_VALUE"),
  "POSTGRES_USER": $(json_quote "$PG_USER"),
  "POSTGRES_PASSWORD": $(json_quote "$PG_PASSWORD"),
  "POSTGRES_DB": $(json_quote "$PG_DB"),
  "COMPOSE_PROFILES": $(json_quote "$COMPOSE_PROFILES")
}
EOF
  ensure_private_file "$ENV_JSON"
  python3 "$ROOT_DIR/py/render_env.py" < "$ENV_JSON" > "$ENV_PATH"

  TOML_JSON="$ROOT_DIR/state/render-config.json"
  cat > "$TOML_JSON" <<EOF
{
  "provider": $(json_quote "$PROVIDER"),
  "model": $(json_quote "$MODEL"),
  "password": $(json_quote "$PASSWORD"),
  "apiKey": $(json_quote "$API_KEY"),
  "authFile": $(json_quote "$AUTH_FILE"),
  "publicHostname": $(json_quote "$PUBLIC_HOSTNAME"),
  "customPrompt": $(json_quote "$CUSTOM_PROMPT"),
  "owner": {
    "name": $(json_quote "$OWNER_NAME"),
    "signal": $(json_quote "$OWNER_SIGNAL"),
    "telegram": $(json_quote "$OWNER_TELEGRAM"),
    "whatsapp": $(json_quote "$OWNER_WHATSAPP"),
    "email": $(json_quote "$OWNER_EMAIL")
  },
  "coder": {
    "model": $(json_quote "$CODER_MODEL")
  },
  "signal": {
    "account": $(json_quote "$SIGNAL_ACCOUNT")
  },
  "telegram": {
    "botToken": $(json_quote "$TELEGRAM_BOT_TOKEN")
  },
  "email": {
    "webhookSecret": $(json_quote "$WEBHOOK_SECRET"),
    "smtpHost": $(json_quote "$SMTP_HOST"),
    "smtpPort": $(json_quote "$SMTP_PORT"),
    "smtpUser": $(json_quote "$SMTP_USER"),
    "smtpPassword": $(json_quote "$SMTP_PASSWORD"),
    "fromAddress": $(json_quote "$FROM_ADDRESS")
  },
  "whatsapp_enabled": $(python3 -c 'import sys; print("true" if sys.argv[1] == "true" else "false")' "$WHATSAPP_ENABLED")
}
EOF
  ensure_private_file "$TOML_JSON"
  python3 "$ROOT_DIR/py/render_toml.py" < "$TOML_JSON" > "$CONFIG_PATH"
  load_runtime_metadata
fi

if (( CONFIG_ONLY )); then
  SKIP_PLUGINS=1
fi

if (( !SKIP_PLUGINS && !REFRESH_ONLY && !SKIP_CONFIG )); then
  if prompt_yes_no "Review plugin installation choices now?" "N"; then
    prompt_plugin_selection
  fi
fi

AFTER_ENV_HASH=$(sha256_file "$ENV_PATH")
AFTER_CONFIG_HASH=$(sha256_file "$CONFIG_PATH")
ENV_CHANGED=false
CONFIG_CHANGED=false
[[ "$BEFORE_ENV_HASH" != "$AFTER_ENV_HASH" ]] && ENV_CHANGED=true
[[ "$BEFORE_CONFIG_HASH" != "$AFTER_CONFIG_HASH" ]] && CONFIG_CHANGED=true

load_runtime_metadata

if (( CONFIG_ONLY )); then
  info "Config-only mode: wrote config files without rebuilding containers or running plugins"
elif (( REFRESH_ONLY )) || [[ "$BEFORE_HEAD" != "$AFTER_HEAD" ]] || [[ "$ENV_CHANGED" == true ]] || [[ "$CONFIG_CHANGED" == true ]]; then
  info "Rebuilding and recreating stavrobot containers"
  docker_compose_up_recreate "$STAVROBOT_DIR"
  wait_for_stavrobot_ready
else
  info "No rebuild needed"
  if [[ -n "$PASSWORD_FOR_READY" ]]; then
    wait_for_stavrobot_ready
  fi
fi

if (( !SKIP_PLUGINS && !CONFIG_ONLY )); then
  run_plugins_from_state
fi

print_run_summary "$BEFORE_HEAD" "$AFTER_HEAD" "$ENV_CHANGED" "$CONFIG_CHANGED" "$PLUGINS_SELECTED_COUNT" "$PLUGINS_HANDLED" "$PLUGIN_REPORT_FILE"
print_next_steps "$PUBLIC_HOSTNAME_FINAL" "$CODER_ENABLED" "$SIGNAL_ENABLED" "$WHATSAPP_ENABLED" "$EMAIL_ENABLED" "$AUTH_MODE_FINAL"
info "See README.md and IMPLEMENTATION_PLAN.md"
