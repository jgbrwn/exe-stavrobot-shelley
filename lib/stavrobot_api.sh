#!/usr/bin/env bash
set -euo pipefail

stavrobot_api_request() {
  local base_url="$1"
  local password="$2"
  local method="$3"
  local path="$4"
  local body="${5-}"

  if [[ -n "$body" ]]; then
    curl -fsS -u "installer:$password" -X "$method" \
      -H 'Content-Type: application/json' \
      "$base_url$path" \
      -d "$body"
  else
    curl -fsS -u "installer:$password" -X "$method" \
      "$base_url$path"
  fi
}

stavrobot_list_plugins() {
  local base_url="$1"
  local password="$2"
  stavrobot_api_request "$base_url" "$password" GET "/api/settings/plugins/list"
}
