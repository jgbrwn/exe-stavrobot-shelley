#!/usr/bin/env bash
set -euo pipefail

stavrobot_api_request() {
  local base_url="$1"
  local password="$2"
  local method="$3"
  local path="$4"
  local body="${5-}"

  if [[ -n "$body" ]]; then
    curl -sS -u "installer:$password" -X "$method" \
      -H 'Content-Type: application/json' \
      "$base_url$path" \
      -d "$body"
  else
    curl -sS -u "installer:$password" -X "$method" \
      "$base_url$path"
  fi
}

stavrobot_list_plugins() {
  local base_url="$1"
  local password="$2"
  stavrobot_api_request "$base_url" "$password" GET "/api/settings/plugins/list"
}

stavrobot_install_plugin() {
  local base_url="$1"
  local password="$2"
  local repo_url="$3"
  local body
  body=$(python3 -c 'import json,sys; print(json.dumps({"url": sys.argv[1]}))' "$repo_url")
  stavrobot_api_request "$base_url" "$password" POST "/api/settings/plugins/install" "$body"
}

stavrobot_configure_plugin() {
  local base_url="$1"
  local password="$2"
  local plugin_name="$3"
  local config_json="$4"
  local body
  body=$(python3 - "$plugin_name" "$config_json" <<'PY'
import json, sys
name = sys.argv[1]
config = json.loads(sys.argv[2])
print(json.dumps({"name": name, "config": config}))
PY
)
  stavrobot_api_request "$base_url" "$password" POST "/api/settings/plugins/configure" "$body"
}
