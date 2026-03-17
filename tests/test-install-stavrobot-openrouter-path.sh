#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

FAKE_STAVROBOT="$TMP_DIR/stavrobot"
mkdir -p "$FAKE_STAVROBOT/data/main"
cat > "$FAKE_STAVROBOT/env.example" <<'EOF_ENV'
TZ=UTC
POSTGRES_USER=stavrobot
POSTGRES_PASSWORD=stavrobot
POSTGRES_DB=stavrobot
EOF_ENV
cp "$FAKE_STAVROBOT/env.example" "$FAKE_STAVROBOT/.env"
cat > "$FAKE_STAVROBOT/config.example.toml" <<'EOF_TOML'
provider = "anthropic"
model = "claude-sonnet-4-20250514"
password = "change-me"
authFile = "/app/data/auth.json"
publicHostname = "https://example.com"

[owner]
name = "Owner"
EOF_TOML
cp "$FAKE_STAVROBOT/config.example.toml" "$FAKE_STAVROBOT/data/main/config.toml"
cat > "$FAKE_STAVROBOT/docker-compose.yml" <<'EOF_DC'
services:
  app:
    image: alpine:latest
EOF_DC
(
  cd "$FAKE_STAVROBOT"
  git init -q
  git config user.name test
  git config user.email test@example.com
  git add .
  git commit -qm 'init'
)
mkdir -p "$ROOT_DIR/state"
cat > "$ROOT_DIR/state/openrouter-free-models.json" <<'EOF_JSON'
{
  "endpoint": "https://openrouter.ai/api/v1",
  "models": [
    {"id": "openrouter/free", "name": "Free Models Router", "context_length": 200000},
    {"id": "qwen/qwen3-coder:free", "name": "Qwen", "context_length": 262000}
  ]
}
EOF_JSON

INPUT=$'\nN\n2\n1\n1\nopenrouter-test-key\nchange-me\nhttps://example.com\nOwner\nSKIP\nSKIP\nSKIP\nSKIP\nN\nN\nN\nN\nN\nN\n'
OUTPUT=$(printf '%s' "$INPUT" | SHELLEY_INSTALLER_TEST_SKIP_OPENROUTER_FETCH=1 "$ROOT_DIR/install-stavrobot.sh" --stavrobot-dir "$FAKE_STAVROBOT" --config-only 2>&1 || true)

assert_contains "$OUTPUT" 'Provider setup:'
assert_contains "$OUTPUT" '  2) OpenRouter'
assert_contains "$OUTPUT" 'OpenRouter auth mode:'
assert_contains "$OUTPUT" 'OpenRouter model:'
assert_contains "$OUTPUT" '  1) openrouter/free'
assert_contains "$OUTPUT" '  2) qwen/qwen3-coder:free'

CONFIG_OUT=$(cat "$FAKE_STAVROBOT/data/main/config.toml")
assert_contains "$CONFIG_OUT" 'provider = "openrouter"'
assert_contains "$CONFIG_OUT" 'model = "openrouter/free"'

printf 'install-stavrobot OpenRouter path test passed\n'
