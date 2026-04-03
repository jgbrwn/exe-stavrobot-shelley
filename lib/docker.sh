#!/usr/bin/env bash
set -euo pipefail

docker_compose_up_recreate() {
  local dir="$1"
  local relay_override="$dir/docker-compose.exedev-email-relay.override.yml"
  if [[ -f "$relay_override" ]]; then
    (cd "$dir" && docker compose -f docker-compose.yml -f docker-compose.exedev-email-relay.override.yml up -d --build --force-recreate)
  else
    (cd "$dir" && docker compose up -d --build --force-recreate)
  fi
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

write_exedev_smtp_relay_override() {
  local dir="$1"
  local owner_email="$2"
  local relay_script_host_path="$3"
  local out_path="$dir/docker-compose.exedev-email-relay.override.yml"
  cat > "$out_path" <<EOF
services:
  app:
    extra_hosts:
      - "host.docker.internal:host-gateway"

  exedev-smtp-relay:
    image: python:3.12-alpine
    restart: unless-stopped
    command: ["python3", "/relay/exedev_smtp_relay.py"]
    environment:
      OWNER_EMAIL: "$owner_email"
      LISTEN_HOST: "0.0.0.0"
      LISTEN_PORT: "2525"
      EXEDEV_SEND_URL: "http://169.254.169.254/gateway/email/send"
    volumes:
      - "$relay_script_host_path:/relay/exedev_smtp_relay.py:ro"
EOF
  chmod 600 "$out_path"
}

remove_exedev_smtp_relay_override() {
  local dir="$1"
  rm -f "$dir/docker-compose.exedev-email-relay.override.yml"
}
