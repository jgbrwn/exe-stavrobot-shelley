#!/usr/bin/env bash
set -euo pipefail

print_run_summary() {
  local before_head="$1"
  local after_head="$2"
  local env_changed="$3"
  local config_changed="$4"
  cat <<EOF
Run summary
-----------
Repo HEAD before: $before_head
Repo HEAD after:  $after_head
.env changed:     $env_changed
config changed:   $config_changed
EOF
}
