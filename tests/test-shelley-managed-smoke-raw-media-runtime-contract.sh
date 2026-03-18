#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SHELLEY_DIR="${SHELLEY_DIR:-/opt/shelley}"
PROFILE_STATE_PATH="${PROFILE_STATE_PATH:-$ROOT_DIR/state/shelley-bridge-profiles.json}"

if [[ ! -x "$SHELLEY_DIR/bin/shelley" ]]; then
  echo "skipping: managed shelley binary not found at $SHELLEY_DIR/bin/shelley"
  exit 0
fi
if [[ ! -f "$PROFILE_STATE_PATH" ]]; then
  echo "skipping: profile state not found at $PROFILE_STATE_PATH"
  exit 0
fi
if [[ ! -f /tmp/stavrobot/data/main/config.toml ]]; then
  echo "skipping: stavrobot config not found at /tmp/stavrobot/data/main/config.toml"
  exit 0
fi
if [[ ! -f "$SHELLEY_DIR/server/stavrobot.go" ]]; then
  echo "skipping: runtime source not found at $SHELLEY_DIR/server/stavrobot.go"
  exit 0
fi
if ! rg -q "hasAssistantText := false" "$SHELLEY_DIR/server/stavrobot.go"; then
  echo "skipping: managed runtime does not yet include native raw-media gating implementation"
  exit 0
fi
if ! rg -q "validateStavrobotRawInlineArtifact" "$SHELLEY_DIR/server/stavrobot.go"; then
  echo "skipping: managed runtime does not yet include raw-media validation helper"
  exit 0
fi

run_smoke() {
  local fixture="$1"
  shift
  local port="$1"
  shift
  local db="/tmp/shelley-managed-smoke-runtime-${fixture}-${port}.db"
  local session="shelley-managed-runtime-${fixture}-${port}"
  "$ROOT_DIR/smoke-test-shelley-managed-s1.sh" \
    --shelley-dir "$SHELLEY_DIR" \
    --shelley-bin "$SHELLEY_DIR/bin/shelley" \
    --profile-state-path "$PROFILE_STATE_PATH" \
    --port "$port" \
    --db-path "$db" \
    --tmux-session "$session" \
    --bridge-fixture "$fixture" \
    "$@" >/dev/null
}

# Case A: no assistant text + valid raw media => native mapping should appear.
run_smoke runtime_raw_media_only 8892 --expect-native-raw-media-gating --require-native-raw-media-hints --expect-media-refs --require-media-refs

# Case B: invalid raw media should be rejected non-fatally.
run_smoke runtime_invalid_raw_media 8893 --expect-raw-media-rejection --require-raw-media-rejection-hints

# Case C: unsupported MIME raw media should be rejected non-fatally.
run_smoke runtime_unsupported_raw_mime 8894 --expect-raw-media-rejection --require-raw-media-rejection-hints

# Case D: oversize raw media should be rejected non-fatally.
run_smoke runtime_oversize_raw_media 8895 --expect-raw-media-rejection --require-raw-media-rejection-hints

echo "shelley managed smoke raw-media runtime contract tests passed"
