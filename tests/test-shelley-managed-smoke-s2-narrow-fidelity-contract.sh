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

if [[ ! -x "$ROOT_DIR/run-shelley-managed-s2-narrow-fidelity-proof.sh" ]]; then
  skip_or_fail "S2 narrow-fidelity helper missing or not executable"
fi
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
if ! rg -q "ProcessStavrobotConversationTurn" "$SHELLEY_DIR/server/stavrobot.go"; then
  skip_or_fail "managed runtime does not include expected runtime turn processing helper"
fi
if ! rg -q "media_refs" "$SHELLEY_DIR/server/stavrobot.go"; then
  skip_or_fail "managed runtime does not include expected media_refs persistence path"
fi
if ! rg -q "mktemp" "$ROOT_DIR/shelley-stavrobot-bridge.sh"; then
  skip_or_fail "bridge does not include argv-safe payload temp-file handling"
fi

"$ROOT_DIR/run-shelley-managed-s2-narrow-fidelity-proof.sh" \
  --shelley-dir "$SHELLEY_DIR" \
  --shelley-bin "$SHELLEY_DIR/bin/shelley" \
  --profile-state-path "$PROFILE_STATE_PATH" \
  --base-port 8912 \
  --db-prefix /tmp/shelley-managed-smoke-s2-runtime \
  --session-prefix shelley-managed-s2-runtime >/dev/null

echo "shelley managed smoke s2 narrow-fidelity contract tests passed"
