#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SHELLEY_DIR="${SHELLEY_DIR:-/opt/shelley}"
PROFILE_STATE_PATH="${PROFILE_STATE_PATH:-$ROOT_DIR/state/shelley-bridge-profiles.json}"
REQUIRE_PATCHED_MANAGED_RUNTIME="${REQUIRE_PATCHED_MANAGED_RUNTIME:-0}"

skip_or_fail() {
  local msg="$1"
  if [[ "$REQUIRE_PATCHED_MANAGED_RUNTIME" == "1" ]]; then
    echo "required-runtime-check failed: $msg" >&2
    exit 1
  fi
  echo "skipping: $msg"
  exit 0
}

if [[ ! -x "$SHELLEY_DIR/bin/shelley" ]]; then
  skip_or_fail "managed shelley binary not found at $SHELLEY_DIR/bin/shelley"
fi
if [[ ! -f "$PROFILE_STATE_PATH" ]]; then
  skip_or_fail "profile state not found at $PROFILE_STATE_PATH"
fi
if [[ ! -f /tmp/stavrobot/data/main/config.toml ]]; then
  skip_or_fail "stavrobot config not found at /tmp/stavrobot/data/main/config.toml"
fi
if [[ ! -f "$SHELLEY_DIR/server/stavrobot.go" ]]; then
  skip_or_fail "runtime source not found at $SHELLEY_DIR/server/stavrobot.go"
fi
if ! rg -q "hasAssistantText := false" "$SHELLEY_DIR/server/stavrobot.go"; then
  skip_or_fail "managed runtime does not yet include native raw-media gating implementation"
fi
if ! rg -q "validateStavrobotRawInlineArtifact" "$SHELLEY_DIR/server/stavrobot.go"; then
  skip_or_fail "managed runtime does not yet include raw-media validation helper"
fi

"$ROOT_DIR/run-shelley-managed-strict-raw-media-proof.sh" \
  --shelley-dir "$SHELLEY_DIR" \
  --shelley-bin "$SHELLEY_DIR/bin/shelley" \
  --profile-state-path "$PROFILE_STATE_PATH" \
  --base-port 8892 \
  --db-prefix /tmp/shelley-managed-smoke-runtime \
  --session-prefix shelley-managed-runtime >/dev/null

echo "shelley managed smoke raw-media runtime contract tests passed"
