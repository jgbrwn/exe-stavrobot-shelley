#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

make_config() {
  local path="$1"
  local provider="$2"
  local model="$3"
  local auth_line="$4"
  cat > "$path" <<EOF_CONFIG
provider = "$provider"
model = "$model"
password = "secret"
$auth_line
EOF_CONFIG
}

CONFIG_OPENROUTER="$TMP_DIR/openrouter.toml"
make_config "$CONFIG_OPENROUTER" "openrouter" "openrouter/free" 'apiKey = "test-key"'

current_out=$("$ROOT_DIR/manage-stavrobot-model.sh" get-current --config-path "$CONFIG_OPENROUTER")
assert_contains "$current_out" '"status": "ok"'
assert_contains "$current_out" '"provider": "openrouter"'
assert_contains "$current_out" '"model": "openrouter/free"'
assert_contains "$current_out" '"openrouter_model_selection_available": true'
assert_contains "$current_out" '"auth_mode": "apiKey"'

CONFIG_ANTHROPIC="$TMP_DIR/anthropic.toml"
make_config "$CONFIG_ANTHROPIC" "anthropic" "claude-sonnet-4-20250514" 'apiKey = "anthropic-key"'

list_fail=$("$ROOT_DIR/manage-stavrobot-model.sh" list-openrouter-free --config-path "$CONFIG_ANTHROPIC" 2>&1 || true)
assert_contains "$list_fail" '"status": "error"'
assert_contains "$list_fail" '"error": "openrouter_not_active"'
assert_contains "$list_fail" '"reason": "provider_is_not_openrouter"'

MODELS_SCRIPT="$TMP_DIR/openrouter_models_stub.py"
cat > "$MODELS_SCRIPT" <<'EOF_MODELS'
#!/usr/bin/env python3
import json
print(json.dumps({
  "models": [
    {"id": "openrouter/free", "name": "Free Models Router", "context_length": 200000},
    {"id": "qwen/qwen3-coder:free", "name": "Qwen", "context_length": 262000}
  ]
}))
EOF_MODELS
chmod +x "$MODELS_SCRIPT"

list_ok=$(OPENROUTER_MODELS_SCRIPT="$MODELS_SCRIPT" "$ROOT_DIR/manage-stavrobot-model.sh" list-openrouter-free --config-path "$CONFIG_OPENROUTER")
assert_contains "$list_ok" '"status": "ok"'
assert_contains "$list_ok" '"source": "openrouter-free"'
assert_contains "$list_ok" '"id": "openrouter/free"'
assert_contains "$list_ok" '"id": "qwen/qwen3-coder:free"'

FAKE_STAVROBOT="$TMP_DIR/stavrobot"
mkdir -p "$FAKE_STAVROBOT/data/main" "$TMP_DIR/bin"
CONFIG_APPLY="$FAKE_STAVROBOT/data/main/config.toml"
make_config "$CONFIG_APPLY" "openrouter" "openrouter/free" 'apiKey = "test-key"'

DOCKER_LOG="$TMP_DIR/docker.log"
cat > "$TMP_DIR/bin/docker" <<EOF_DOCKER
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "$DOCKER_LOG"
if [[ "\${1:-}" == compose && "\${2:-}" == restart && "\${3:-}" == app ]]; then
  exit 0
fi
if [[ "\${1:-}" == compose && "\${2:-}" == up && "\${3:-}" == -d && "\${4:-}" == --force-recreate && "\${5:-}" == app ]]; then
  exit 0
fi
printf 'unexpected docker invocation: %s\n' "\$*" >&2
exit 1
EOF_DOCKER
chmod +x "$TMP_DIR/bin/docker"

CLIENT_STUB="$TMP_DIR/client-stub.sh"
cat > "$CLIENT_STUB" <<'EOF_CLIENT'
#!/usr/bin/env bash
set -euo pipefail
config_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-path)
      config_path="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
python3 - "$config_path" <<'PY'
import json, sys, tomllib
cfg = tomllib.loads(open(sys.argv[1]).read())
print(json.dumps({
  "ok": True,
  "provider": cfg.get("provider", ""),
  "model": cfg.get("model", "")
}))
PY
EOF_CLIENT
chmod +x "$CLIENT_STUB"

apply_out=$(PATH="$TMP_DIR/bin:$PATH" STAVROBOT_CLIENT_BIN="$CLIENT_STUB" "$ROOT_DIR/manage-stavrobot-model.sh" apply --stavrobot-dir "$FAKE_STAVROBOT" --model qwen/qwen3-coder:free)
assert_contains "$apply_out" '"status": "ok"'
assert_contains "$apply_out" '"operation": "restart"'
assert_contains "$apply_out" '"previous_model": "openrouter/free"'
assert_contains "$apply_out" '"current_model": "qwen/qwen3-coder:free"'
assert_contains "$apply_out" '"ready": true'

config_after=$(cat "$CONFIG_APPLY")
assert_contains "$config_after" 'model = "qwen/qwen3-coder:free"'

docker_calls=$(cat "$DOCKER_LOG")
assert_contains "$docker_calls" 'compose restart app'

printf 'manage-stavrobot-model tests passed\n'
