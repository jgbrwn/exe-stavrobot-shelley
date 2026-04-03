#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/prompts.sh"

STAVROBOT_DIR=""
CONFIG_PATH=""
MAILDIR_ROOT="${MAILDIR_ROOT:-$HOME/Maildir}"
SERVICE_NAME="stavrobot-exedev-email-bridge"
INSTALL_SERVICE=1
DISABLE_SERVICE=0
SHOW_SECRETS=0
POLL_INTERVAL_SECONDS="2"
REQUEST_TIMEOUT_SECONDS="10"
PUBLIC_HOSTNAME=""
WEBHOOK_SECRET=""
WEBHOOK_URL=""

usage() {
  cat <<'EOF'
Usage: ./install-exedev-email-bridge.sh [flags]

Flags:
  --stavrobot-dir PATH         Read publicHostname and email.webhookSecret from config.toml
  --config-path PATH           Read config directly from a config.toml file
  --maildir-root PATH          Maildir root to watch (default: ~/Maildir)
  --service-name NAME          systemd service name (default: stavrobot-exedev-email-bridge)
  --poll-interval-seconds N    Poll interval for Maildir scanning (default: 2)
  --request-timeout-seconds N  Webhook request timeout (default: 10)
  --public-hostname URL        Override or supply public hostname
  --webhook-secret SECRET      Override or supply email webhook secret
  --no-install-service         Render env/unit files only; do not install/start service
  --disable-service            Stop + disable the service
  --show-secrets               Show secret defaults in prompts
  --help

Notes:
  - This is for exe.dev inbound email receiving (Maildir) -> Stavrobot /email/webhook
  - Enable receive-email separately via: ssh exe.dev share receive-email <vmname> on
EOF
}

resolve_config_path() {
  if [[ -n "$CONFIG_PATH" ]]; then
    return 0
  fi
  if [[ -n "$STAVROBOT_DIR" ]]; then
    CONFIG_PATH="$STAVROBOT_DIR/data/main/config.toml"
  fi
}

load_values_from_config() {
  [[ -n "$CONFIG_PATH" ]] || return 0
  [[ -f "$CONFIG_PATH" ]] || die "Config file not found: $CONFIG_PATH"
  eval "$(python3 - "$CONFIG_PATH" <<'PY'
import sys, tomllib
from pathlib import Path
path = Path(sys.argv[1])
data = tomllib.loads(path.read_text())
public_hostname = data.get('publicHostname', '')
webhook_secret = ((data.get('email') or {}).get('webhookSecret', ''))
print(f'CONFIG_PUBLIC_HOSTNAME={public_hostname!r}')
print(f'CONFIG_WEBHOOK_SECRET={webhook_secret!r}')
PY
)"
  if [[ -z "$PUBLIC_HOSTNAME" ]]; then
    PUBLIC_HOSTNAME="$CONFIG_PUBLIC_HOSTNAME"
  fi
  if [[ -z "$WEBHOOK_SECRET" ]]; then
    WEBHOOK_SECRET="$CONFIG_WEBHOOK_SECRET"
  fi
}

render_service_files() {
  local state_dir="$ROOT_DIR/state/exedev-email-bridge"
  mkdir -p "$state_dir"
  local env_file="$state_dir/${SERVICE_NAME}.env"
  local unit_file="$state_dir/${SERVICE_NAME}.service"

  cat > "$env_file" <<EOF
WEBHOOK_URL=$WEBHOOK_URL
WEBHOOK_SECRET=$WEBHOOK_SECRET
MAILDIR_ROOT=$MAILDIR_ROOT
POLL_INTERVAL_SECONDS=$POLL_INTERVAL_SECONDS
REQUEST_TIMEOUT_SECONDS=$REQUEST_TIMEOUT_SECONDS
EOF
  chmod 600 "$env_file"

  cat > "$unit_file" <<EOF
[Unit]
Description=Stavrobot exe.dev email Maildir bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
Group=$(id -gn)
EnvironmentFile=$env_file
ExecStart=/usr/bin/env python3 $ROOT_DIR/scripts/exedev_email_webhook_bridge.py --maildir-root "\${MAILDIR_ROOT}" --webhook-url "\${WEBHOOK_URL}" --webhook-secret "\${WEBHOOK_SECRET}" --poll-interval-seconds "\${POLL_INTERVAL_SECONDS}" --request-timeout-seconds "\${REQUEST_TIMEOUT_SECONDS}"
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

  printf '%s\n' "$env_file"
  printf '%s\n' "$unit_file"
}

install_service() {
  local unit_file="$1"
  sudo cp "$unit_file" "/etc/systemd/system/${SERVICE_NAME}.service"
  sudo systemctl daemon-reload
  sudo systemctl enable --now "$SERVICE_NAME"
}

disable_service() {
  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    sudo systemctl disable --now "$SERVICE_NAME" || true
    sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    sudo systemctl daemon-reload
    info "Disabled and removed ${SERVICE_NAME}.service"
  else
    info "Service ${SERVICE_NAME}.service is not installed"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stavrobot-dir)
      STAVROBOT_DIR="$2"
      shift 2
      ;;
    --config-path)
      CONFIG_PATH="$2"
      shift 2
      ;;
    --maildir-root)
      MAILDIR_ROOT="$2"
      shift 2
      ;;
    --service-name)
      SERVICE_NAME="$2"
      shift 2
      ;;
    --poll-interval-seconds)
      POLL_INTERVAL_SECONDS="$2"
      shift 2
      ;;
    --request-timeout-seconds)
      REQUEST_TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --public-hostname)
      PUBLIC_HOSTNAME="$2"
      shift 2
      ;;
    --webhook-secret)
      WEBHOOK_SECRET="$2"
      shift 2
      ;;
    --no-install-service)
      INSTALL_SERVICE=0
      shift
      ;;
    --disable-service)
      DISABLE_SERVICE=1
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

if (( DISABLE_SERVICE )); then
  disable_service
  exit 0
fi

require_cmd python3
resolve_config_path
load_values_from_config

if [[ -z "$PUBLIC_HOSTNAME" ]]; then
  PUBLIC_HOSTNAME=$(prompt_text "Public HTTPS URL" "")
fi
PUBLIC_HOSTNAME=${PUBLIC_HOSTNAME%/}
[[ "$PUBLIC_HOSTNAME" =~ ^https?:// ]] || die "publicHostname must start with http:// or https://"
WEBHOOK_URL="$PUBLIC_HOSTNAME/email/webhook"

if [[ -z "$WEBHOOK_SECRET" ]]; then
  if [[ -t 0 ]]; then
    WEBHOOK_SECRET=$(prompt_secret "Email webhook secret" "")
  fi
else
  if [[ -t 0 ]]; then
    local_secret_default="$WEBHOOK_SECRET"
    if (( SHOW_SECRETS )); then
      WEBHOOK_SECRET=$(prompt_secret "Email webhook secret" "$local_secret_default")
    else
      WEBHOOK_SECRET=$(prompt_secret "Email webhook secret" "$(mask_secret "$local_secret_default")")
    fi
    WEBHOOK_SECRET=${WEBHOOK_SECRET:-$local_secret_default}
  fi
fi
[[ -n "$WEBHOOK_SECRET" ]] || die "email.webhookSecret is required"

mapfile -t rendered < <(render_service_files)
ENV_FILE="${rendered[0]}"
UNIT_FILE="${rendered[1]}"

if (( INSTALL_SERVICE )); then
  install_service "$UNIT_FILE"
fi

cat <<EOF
exe.dev email bridge rendered.

Maildir root:    $MAILDIR_ROOT
Webhook URL:     $WEBHOOK_URL
Webhook secret:  $(mask_secret "$WEBHOOK_SECRET")
Service name:    $SERVICE_NAME
Env file:        $ENV_FILE
Unit file:       $UNIT_FILE

Next steps:
  1) Enable exe.dev receive-email (once):
     ssh exe.dev share receive-email <vmname> on
  2) Send a test email to any.address@<vmname>.exe.xyz
  3) Check service logs:
     sudo journalctl -u $SERVICE_NAME -f
EOF
