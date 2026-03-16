#!/usr/bin/env bash
set -euo pipefail

print_run_summary() {
  local before_head="$1"
  local after_head="$2"
  local env_changed="$3"
  local config_changed="$4"
  local plugins_selected="$5"
  local plugins_handled="$6"
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
}

print_next_steps() {
  local public_hostname="$1"
  local coder_enabled="$2"
  local signal_enabled="$3"
  local whatsapp_enabled="$4"
  cat <<EOF

Next steps
----------
Public hostname: $public_hostname
EOF
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
}
