#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/repo.sh"

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

validate_stavrobot_repo "$STAVROBOT_DIR"

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

if (( PLUGINS_ONLY )); then
  info "Phase 1 plugin-only mode is planned but not implemented yet"
  exit 0
fi

if (( REFRESH_ONLY )); then
  info "Phase 1 refresh path currently stops after upstream update"
  exit 0
fi

if (( CONFIG_ONLY || !SKIP_CONFIG )); then
  info "Phase 1 next implementation step: interactive config generation"
fi

if (( !SKIP_PLUGINS )); then
  info "Phase 1 next implementation step: plugin prompt and install flow"
fi

OPENROUTER_OUT="$ROOT_DIR/state/openrouter-free-models.json"
if python3 "$ROOT_DIR/py/openrouter_models.py" > "$OPENROUTER_OUT"; then
  ensure_private_file "$OPENROUTER_OUT"
  info "Fetched OpenRouter free model suggestions into $OPENROUTER_OUT"
else
  warn "Failed to fetch OpenRouter free model suggestions"
fi

info "Scaffold complete. See README.md and IMPLEMENTATION_PLAN.md"
