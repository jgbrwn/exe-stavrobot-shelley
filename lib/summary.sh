#!/usr/bin/env bash
set -euo pipefail

print_run_summary() {
  local before_head="$1"
  local after_head="$2"
  local env_changed="$3"
  local config_changed="$4"
  local plugins_selected="$5"
  local plugins_handled="$6"
  local plugin_report="${7-}"
  cat <<EOF
Run summary
-----------
Repo HEAD before: $before_head
Repo HEAD after:  $after_head
.env changed:     $env_changed
config changed:   $config_changed
Plugins selected: $plugins_selected
Plugins handled:  $plugins_handled
EOF
  if [[ -n "$plugin_report" && -f "$plugin_report" && -s "$plugin_report" ]]; then
    printf 'Plugin results:\n'
    sed 's/^/  - /' "$plugin_report"
  fi
}

print_next_steps() {
  local public_hostname="$1"
  local coder_enabled="$2"
  local signal_enabled="$3"
  local whatsapp_enabled="$4"
  local email_enabled="$5"
  local auth_mode="$6"
  cat <<EOF

Next steps
----------
Public hostname: $public_hostname
EOF
  if [[ "$auth_mode" == "authFile" ]]; then
    cat <<'EOF'
- authFile mode is enabled. Complete OAuth login after startup using the provider login flow described in the upstream README.
EOF
  fi
  if [[ "$coder_enabled" == "true" ]]; then
    cat <<'EOF'
- Coder is enabled. Complete Claude Code login with:
  docker compose exec -u coder coder claude
EOF
  fi
  if [[ "$signal_enabled" == "true" ]]; then
    cat <<'EOF'
- Signal is enabled. Complete Signal setup using the commands in the upstream README.
EOF
  fi
  if [[ "$whatsapp_enabled" == "true" ]]; then
    cat <<'EOF'
- WhatsApp is enabled. Watch logs for the QR code:
  docker compose logs -f app
EOF
  fi
  if [[ "$email_enabled" == "true" ]]; then
    cat <<'EOF'
- Email config is present. Cloudflare Email Worker deployment is still manual in Phase 1.
EOF
  fi
}
