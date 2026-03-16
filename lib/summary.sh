#!/usr/bin/env bash
set -euo pipefail

print_run_summary() {
  local before_head="$1"
  local after_head="$2"
  cat <<EOF
Run summary
-----------
Repo HEAD before: $before_head
Repo HEAD after:  $after_head
EOF
}
