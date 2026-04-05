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

out=$(printf '\nN\n1\n1\nclaude-sonnet-4-20250514\nkey\nchange-me\nhttps://example.com\nOwner\nSKIP\nSKIP\nSKIP\nSKIP\nN\nN\nN\nN\nN\nN\n' | \
  SHELLEY_INSTALLER_TEST_SKIP_OPENROUTER_FETCH=1 "$ROOT_DIR/install-stavrobot.sh" --stavrobot-dir "$FAKE_STAVROBOT" --config-only 2>&1)
assert_contains "$out" 'Config-only path: skipping upstream stavrobot pull'
assert_contains "$out" 'Config-only mode: wrote config files without rebuilding containers or running plugins'

FAKE_STAVROBOT2="$TMP_DIR/stavrobot-skip"
cp -R "$FAKE_STAVROBOT" "$FAKE_STAVROBOT2"
python3 - <<'PY' "$FAKE_STAVROBOT2/data/main/config.toml"
from pathlib import Path
p = Path(__import__('sys').argv[1])
p.write_text(p.read_text().replace('password = "change-me"\n', ''))
PY
out=$(SHELLEY_INSTALLER_TEST_SKIP_OPENROUTER_FETCH=1 "$ROOT_DIR/install-stavrobot.sh" --stavrobot-dir "$FAKE_STAVROBOT2" --skip-config --skip-plugins 2>&1 || true)
assert_contains "$out" 'Skip-config mode: reusing existing config files'
assert_contains "$out" 'No rebuild needed'

printf 'install-stavrobot config-mode tests passed\n'

TMP_CLONE_ROOT=$(mktemp -d)
NEW_STAVROBOT_DIR="$TMP_CLONE_ROOT/stavrobot-new"
out=$(SHELLEY_INSTALLER_TEST_SKIP_OPENROUTER_FETCH=1 "$ROOT_DIR/install-stavrobot.sh" --stavrobot-dir "$NEW_STAVROBOT_DIR" --skip-config --skip-plugins 2>&1 || true)
assert_contains "$out" "Cloning stavrobot into $NEW_STAVROBOT_DIR"
assert_contains "$out" "Skip-config mode: reusing existing config files"
rm -rf "$TMP_CLONE_ROOT"

FAKE_STAVROBOT3="$TMP_DIR/stavrobot-noninteractive-email"
cp -R "$FAKE_STAVROBOT" "$FAKE_STAVROBOT3"
out=$(printf '\nN\n1\n1\nclaude-sonnet-4-20250514\nkey\nchange-me\nhttps://example.com\nOwner\nSKIP\nSKIP\nSKIP\nSKIP\nN\nN\nN\nN\nN\nN\n' | \
  SHELLEY_INSTALLER_TEST_SKIP_OPENROUTER_FETCH=1 "$ROOT_DIR/install-stavrobot.sh" \
    --stavrobot-dir "$FAKE_STAVROBOT3" \
    --config-only \
    --email-mode exedev-relay \
    --email-webhook-secret test-webhook-secret \
    --email-owner owner@example.com 2>&1)
assert_contains "$out" 'Config-only mode: wrote config files without rebuilding containers or running plugins'
assert_contains "$out" 'exe.dev relay outbound enabled (recipient must be exactly: owner@example.com)'
if [[ ! -f "$FAKE_STAVROBOT3/docker-compose.exedev-email-relay.override.yml" ]]; then
  echo 'expected exedev email relay override file to exist' >&2
  exit 1
fi
