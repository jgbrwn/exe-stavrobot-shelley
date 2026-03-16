#!/usr/bin/env bash
set -euo pipefail

docker_compose_up_recreate() {
  local dir="$1"
  (cd "$dir" && docker compose up -d --build --force-recreate)
}

wait_for_http_basic_auth() {
  local url="$1"
  local password="$2"
  local timeout_seconds="$3"
  local start
  start=$(date +%s)
  while true; do
    if curl -fsS -u "installer:$password" "$url" >/dev/null 2>&1; then
      return 0
    fi
    if (( $(date +%s) - start >= timeout_seconds )); then
      return 1
    fi
    sleep 2
  done
}
