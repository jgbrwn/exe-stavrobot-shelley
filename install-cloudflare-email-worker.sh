#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/prompts.sh"

STAVROBOT_DIR=""
CONFIG_PATH=""
OUT_DIR="$ROOT_DIR/state/cloudflare-email-worker"
WORKER_NAME="stavrobot-email-worker"
ACCOUNT_ID=""
COMPATIBILITY_DATE="$(date -u +%F)"
DEPLOY=0
SHOW_SECRETS=0
PUBLIC_HOSTNAME=""
WEBHOOK_SECRET=""
WEBHOOK_URL=""
EMAIL_DOMAIN=""

usage() {
  cat <<'EOF'
Usage: ./install-cloudflare-email-worker.sh [flags]

Flags:
  --stavrobot-dir PATH         Read publicHostname and email.webhookSecret from config.toml
  --config-path PATH           Read config directly from a config.toml file
  --public-hostname URL        Override or supply public hostname
  --webhook-secret SECRET      Override or supply email webhook secret
  --out-dir PATH               Output directory for worker bundle
  --worker-name NAME           Cloudflare Worker name
  --account-id ID              Optional Cloudflare account ID for wrangler.toml
  --compatibility-date DATE    Wrangler compatibility date (YYYY-MM-DD)
  --deploy                     Run wrangler deploy and secret upload after rendering
  --show-secrets               Show secret defaults in prompts
  --help

Notes:
  - Generates worker.js, wrangler.toml, .dev.vars.example, README.md, and CHECKLIST.md
  - Cloudflare Email Routing rule creation is still manual
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

render_bundle() {
  mkdir -p "$OUT_DIR"
  local render_cmd=(
    python3 "$ROOT_DIR/py/render_cloudflare_email_worker.py"
    --public-hostname "$PUBLIC_HOSTNAME"
    --webhook-secret "$WEBHOOK_SECRET"
    --worker-name "$WORKER_NAME"
    --compatibility-date "$COMPATIBILITY_DATE"
    --out-dir "$OUT_DIR"
  )
  if [[ -n "$ACCOUNT_ID" ]]; then
    render_cmd+=(--account-id "$ACCOUNT_ID")
  fi
  "${render_cmd[@]}"
  if [[ -f "$OUT_DIR/.dev.vars.example" ]]; then
    chmod 600 "$OUT_DIR/.dev.vars.example"
  fi
}

deploy_bundle() {
  local -a wrangler_cmd
  if command -v wrangler >/dev/null 2>&1; then
    wrangler_cmd=(wrangler)
  elif command -v npx >/dev/null 2>&1; then
    wrangler_cmd=(npx wrangler)
  else
    die "--deploy requires wrangler or npx"
  fi

  info "Deploying Cloudflare worker from $OUT_DIR"
  (cd "$OUT_DIR" && "${wrangler_cmd[@]}" deploy)
  info "Uploading WEBHOOK_SECRET secret"
  (cd "$OUT_DIR" && printf '%s' "$WEBHOOK_SECRET" | "${wrangler_cmd[@]}" secret put WEBHOOK_SECRET)
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
    --public-hostname)
      PUBLIC_HOSTNAME="$2"
      shift 2
      ;;
    --webhook-secret)
      WEBHOOK_SECRET="$2"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --worker-name)
      WORKER_NAME="$2"
      shift 2
      ;;
    --account-id)
      ACCOUNT_ID="$2"
      shift 2
      ;;
    --compatibility-date)
      COMPATIBILITY_DATE="$2"
      shift 2
      ;;
    --deploy)
      DEPLOY=1
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

require_cmd python3
resolve_config_path
load_values_from_config

if [[ -z "$PUBLIC_HOSTNAME" ]]; then
  PUBLIC_HOSTNAME=$(prompt_text "Public HTTPS URL" "")
fi
PUBLIC_HOSTNAME=${PUBLIC_HOSTNAME%/}
[[ "$PUBLIC_HOSTNAME" =~ ^https?:// ]] || die "publicHostname must start with http:// or https://"

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

WEBHOOK_URL="$PUBLIC_HOSTNAME/email/webhook"
EMAIL_DOMAIN=$(python3 - "$PUBLIC_HOSTNAME" <<'PY'
from urllib.parse import urlparse
import sys
print(urlparse(sys.argv[1]).hostname or '')
PY
)
render_bundle

cat <<EOF
Cloudflare email worker bundle rendered.

Output directory: $OUT_DIR
Worker name:      $WORKER_NAME
Email domain:     $EMAIL_DOMAIN
Webhook URL:      $WEBHOOK_URL
Webhook secret:   $(mask_secret "$WEBHOOK_SECRET")

Generated files:
  - $OUT_DIR/worker.js
  - $OUT_DIR/wrangler.toml
  - $OUT_DIR/.dev.vars.example
  - $OUT_DIR/README.md
  - $OUT_DIR/CHECKLIST.md

Next steps:
  1. Review worker.js and CHECKLIST.md in $OUT_DIR
  2. Authenticate Wrangler if needed: wrangler login
  3. Deploy: (cd $OUT_DIR && wrangler deploy)
  4. Upload secret: (cd $OUT_DIR && wrangler secret put WEBHOOK_SECRET)
  5. In Cloudflare Email Routing for $EMAIL_DOMAIN, route inbound mail to worker '$WORKER_NAME'
  6. Send a test email and verify Stavrobot app logs
EOF

if (( DEPLOY )); then
  deploy_bundle
fi
