#!/usr/bin/env bash
set -euo pipefail

docker_compose_up_recreate() {
  local dir="$1"
  local relay_override="$dir/docker-compose.exedev-email-relay.override.yml"
  local modal_override="$dir/docker-compose.private-modal-llm.override.yml"
  local -a compose_args=(docker compose -f docker-compose.yml)

  if [[ -f "$relay_override" ]]; then
    compose_args+=(-f docker-compose.exedev-email-relay.override.yml)
  fi
  if [[ -f "$modal_override" ]]; then
    compose_args+=(-f docker-compose.private-modal-llm.override.yml)
  fi

  compose_args+=(up -d --build --force-recreate)
  (cd "$dir" && "${compose_args[@]}")
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

write_private_modal_llm_override() {
  local dir="$1"
  local proxy_script_host_path="$2"
  local upstream_base_url="$3"
  local modal_token_id="$4"
  local modal_token_secret="$5"
  local listen_port="${6:-11435}"
  local out_path="$dir/docker-compose.private-modal-llm.override.yml"

  cat > "$out_path" <<EOF
services:
  app:
    extra_hosts:
      - "host.docker.internal:host-gateway"

  private-modal-llm-proxy:
    image: python:3.12-alpine
    restart: unless-stopped
    command: ["python3", "/proxy/modal_openai_proxy.py"]
    environment:
      LISTEN_HOST: "0.0.0.0"
      LISTEN_PORT: "$listen_port"
      UPSTREAM_BASE_URL: "$upstream_base_url"
      MODAL_TOKEN_ID: "$modal_token_id"
      MODAL_TOKEN_SECRET: "$modal_token_secret"
      REQUEST_TIMEOUT_SECONDS: "600"
    volumes:
      - "$proxy_script_host_path:/proxy/modal_openai_proxy.py:ro"
EOF
  chmod 600 "$out_path"
}

remove_private_modal_llm_override() {
  local dir="$1"
  rm -f "$dir/docker-compose.private-modal-llm.override.yml"
}
