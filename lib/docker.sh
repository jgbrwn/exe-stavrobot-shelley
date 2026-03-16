#!/usr/bin/env bash
set -euo pipefail

docker_compose_up_recreate() {
  local dir="$1"
  (cd "$dir" && docker compose up -d --build --force-recreate)
}
