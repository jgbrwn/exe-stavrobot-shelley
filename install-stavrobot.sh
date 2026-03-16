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

usage() {
  cat <<'EOF'
Usage: ./install-stavrobot.sh --stavrobot-dir PATH [flags]

Flags:
  --stavrobot-dir PATH
  --refresh
  --plugins-only
  --config-only
  --skip-config
  --skip-plugins
  --show-secrets
  --help
EOF
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
    --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$STAVROBOT_DIR" ]] || die "--stavrobot-dir is required"

require_cmd git
require_cmd python3
require_cmd docker
require_cmd curl

validate_stavrobot_repo "$STAVROBOT_DIR"
mkdir -p "$ROOT_DIR/state"

info "Documented plan: $ROOT_DIR/IMPLEMENTATION_PLAN.md"
info "Validating upstream stavrobot repo"
check_repo_clean_for_pull "$STAVROBOT_DIR"
BEFORE_HEAD=$(get_repo_head "$STAVROBOT_DIR")
pull_latest_stavrobot "$STAVROBOT_DIR"
AFTER_HEAD=$(get_repo_head "$STAVROBOT_DIR")

if [[ "$BEFORE_HEAD" != "$AFTER_HEAD" ]]; then
  info "Updated stavrobot from $BEFORE_HEAD to $AFTER_HEAD"
else
  info "Stavrobot already up to date at $AFTER_HEAD"
fi

OPENROUTER_OUT="$ROOT_DIR/state/openrouter-free-models.json"
if python3 "$ROOT_DIR/py/openrouter_models.py" > "$OPENROUTER_OUT"; then
  ensure_private_file "$OPENROUTER_OUT"
  info "Fetched OpenRouter free model suggestions into $OPENROUTER_OUT"
else
  warn "Failed to fetch OpenRouter free model suggestions"
fi

if (( PLUGINS_ONLY )); then
  info "Phase 1 plugin-only mode is planned but not implemented yet"
  exit 0
fi

ENV_PATH="$STAVROBOT_DIR/.env"
CONFIG_PATH="$STAVROBOT_DIR/data/main/config.toml"
mkdir -p "$(dirname "$CONFIG_PATH")"

BEFORE_ENV_HASH=$(sha256_file "$ENV_PATH")
BEFORE_CONFIG_HASH=$(sha256_file "$CONFIG_PATH")

if (( REFRESH_ONLY )); then
  info "Refresh mode: skipping config prompts"
else
  CURRENT_JSON="$ROOT_DIR/state/current-config.json"
  python3 "$ROOT_DIR/py/load_current_config.py" \
    "$STAVROBOT_DIR/env.example" \
    "$ENV_PATH" \
    "$STAVROBOT_DIR/config.example.toml" \
    "$CONFIG_PATH" > "$CURRENT_JSON"
  ensure_private_file "$CURRENT_JSON"

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

  PROVIDER_MODE=$(prompt_choice "Provider setup:" "Anthropic" "OpenAI-compatible" "Manual/custom")

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
    OpenAI-compatible)
      warn "Current upstream stavrobot config exposes provider and model, but no explicit base URL field. OpenAI-compatible setups may require upstream support beyond this installer."
      printf 'OpenRouter endpoint suggestion: https://openrouter.ai/api/v1\n' >&2
      python3 - "$OPENROUTER_OUT" <<'PY' >&2 || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    for index, model in enumerate(data.get('models', [])[:12], start=1):
        print(f"  {index}) {model['id']}")
except Exception:
    pass
PY
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

  OWNER_NAME=$(prompt_text "Owner name" "$OWNER_NAME_DEFAULT")
  OWNER_NAME=${OWNER_NAME:-$OWNER_NAME_DEFAULT}
  [[ -n "$OWNER_NAME" ]] || die "Owner name is required by stavrobot"

  OWNER_SIGNAL_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.signal)
  OWNER_SIGNAL=$(prompt_text "Owner Signal number (optional)" "$OWNER_SIGNAL_DEFAULT")
  OWNER_SIGNAL=${OWNER_SIGNAL:-$OWNER_SIGNAL_DEFAULT}

  OWNER_TELEGRAM_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.telegram)
  OWNER_TELEGRAM=$(prompt_text "Owner Telegram chat ID (optional)" "$OWNER_TELEGRAM_DEFAULT")
  OWNER_TELEGRAM=${OWNER_TELEGRAM:-$OWNER_TELEGRAM_DEFAULT}

  OWNER_WHATSAPP_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.whatsapp)
  OWNER_WHATSAPP=$(prompt_text "Owner WhatsApp number (optional)" "$OWNER_WHATSAPP_DEFAULT")
  OWNER_WHATSAPP=${OWNER_WHATSAPP:-$OWNER_WHATSAPP_DEFAULT}

  OWNER_EMAIL_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.email)
  OWNER_EMAIL=$(prompt_text "Owner email address (optional)" "$OWNER_EMAIL_DEFAULT")
  OWNER_EMAIL=${OWNER_EMAIL:-$OWNER_EMAIL_DEFAULT}

  TELEGRAM_ENABLED=0
  TELEGRAM_BOT_TOKEN=""
  if prompt_yes_no "Enable Telegram integration?" "N"; then
    TELEGRAM_ENABLED=1
    TELEGRAM_BOT_TOKEN=$(prompt_secret "Telegram bot token" "")
  fi

  SIGNAL_ENABLED=0
  SIGNAL_ACCOUNT=""
  COMPOSE_PROFILES=""
  if prompt_yes_no "Enable Signal integration?" "N"; then
    SIGNAL_ENABLED=1
    COMPOSE_PROFILES="signal"
    SIGNAL_ACCOUNT=$(prompt_text "Signal bot account number" "")
  fi

  WHATSAPP_ENABLED=0
  if prompt_yes_no "Enable WhatsApp integration?" "N"; then
    WHATSAPP_ENABLED=1
  fi

  CODER_ENABLED=0
  CODER_MODEL=""
  if prompt_yes_no "Enable coder container?" "N"; then
    CODER_ENABLED=1
    CODER_MODEL=$(prompt_choice "Coder model:" "sonnet" "opus" "haiku")
  fi

  CUSTOM_PROMPT=""
  if prompt_yes_no "Configure custom prompt?" "N"; then
    CUSTOM_PROMPT=$(prompt_multiline "Enter custom prompt")
  fi

  ENV_JSON="$ROOT_DIR/state/render-env.json"
  cat > "$ENV_JSON" <<EOF
{
  "TZ": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$TZ_VALUE"),
  "POSTGRES_USER": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$PG_USER"),
  "POSTGRES_PASSWORD": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$PG_PASSWORD"),
  "POSTGRES_DB": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$PG_DB"),
  "COMPOSE_PROFILES": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$COMPOSE_PROFILES")
}
EOF
  ensure_private_file "$ENV_JSON"
  python3 "$ROOT_DIR/py/render_env.py" < "$ENV_JSON" > "$ENV_PATH"

  TOML_JSON="$ROOT_DIR/state/render-config.json"
  cat > "$TOML_JSON" <<EOF
{
  "provider": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$PROVIDER"),
  "model": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$MODEL"),
  "password": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$PASSWORD"),
  "apiKey": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$API_KEY"),
  "authFile": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$AUTH_FILE"),
  "publicHostname": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$PUBLIC_HOSTNAME"),
  "customPrompt": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$CUSTOM_PROMPT"),
  "owner": {
    "name": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$OWNER_NAME"),
    "signal": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$OWNER_SIGNAL"),
    "telegram": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$OWNER_TELEGRAM"),
    "whatsapp": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$OWNER_WHATSAPP"),
    "email": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$OWNER_EMAIL")
  },
  "coder": {
    "model": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$CODER_MODEL")
  },
  "signal": {
    "account": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$SIGNAL_ACCOUNT")
  },
  "telegram": {
    "botToken": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$TELEGRAM_BOT_TOKEN")
  },
  "whatsapp_enabled": $(python3 -c 'import json,sys; print("true" if sys.argv[1] == "1" else "false")' "$WHATSAPP_ENABLED")
}
EOF
  ensure_private_file "$TOML_JSON"
  python3 "$ROOT_DIR/py/render_toml.py" < "$TOML_JSON" > "$CONFIG_PATH"
fi

AFTER_ENV_HASH=$(sha256_file "$ENV_PATH")
AFTER_CONFIG_HASH=$(sha256_file "$CONFIG_PATH")
ENV_CHANGED=false
CONFIG_CHANGED=false
[[ "$BEFORE_ENV_HASH" != "$AFTER_ENV_HASH" ]] && ENV_CHANGED=true
[[ "$BEFORE_CONFIG_HASH" != "$AFTER_CONFIG_HASH" ]] && CONFIG_CHANGED=true

print_run_summary "$BEFORE_HEAD" "$AFTER_HEAD" "$ENV_CHANGED" "$CONFIG_CHANGED"

if (( REFRESH_ONLY )) || [[ "$BEFORE_HEAD" != "$AFTER_HEAD" ]] || [[ "$ENV_CHANGED" == true ]] || [[ "$CONFIG_CHANGED" == true ]]; then
  info "Rebuilding and recreating stavrobot containers"
  docker_compose_up_recreate "$STAVROBOT_DIR"
  LOCAL_BASE_URL="http://localhost:10567"
  PASSWORD_FOR_READY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["password"])' "$ROOT_DIR/state/render-config.json" 2>/dev/null || true)
  if [[ -n "$PASSWORD_FOR_READY" ]]; then
    if wait_for_http_basic_auth "$LOCAL_BASE_URL/" "$PASSWORD_FOR_READY" 120; then
      info "Stavrobot is responding at $LOCAL_BASE_URL"
      if stavrobot_list_plugins "$LOCAL_BASE_URL" "$PASSWORD_FOR_READY" >/dev/null 2>&1; then
        info "Plugin settings endpoint is reachable"
      else
        warn "Plugin settings endpoint check failed"
      fi
    else
      warn "Stavrobot did not become ready within timeout"
    fi
  fi
else
  info "No rebuild needed"
fi

info "Phase 1 plugin prompt and install flow is the next implementation step"
info "See README.md and IMPLEMENTATION_PLAN.md"
