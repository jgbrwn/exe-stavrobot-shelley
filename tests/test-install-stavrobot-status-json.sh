#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

STATE="$TMP_DIR/shelley-mode-build.json"
PROFILES="$TMP_DIR/shelley-bridge-profiles.json"
BRIDGE="$TMP_DIR/bridge.sh"
CONFIG="$TMP_DIR/config.toml"
BINARY="$TMP_DIR/bin/shelley"
mkdir -p "$(dirname "$BINARY")"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BRIDGE"
chmod +x "$BRIDGE"
printf 'provider = "openrouter"\n' > "$CONFIG"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINARY"
chmod +x "$BINARY"

cat > "$STATE" <<EOF_STATE
{
  "enabled": true,
  "mode": "stavrobot",
  "local_contract": {"bridge_contract_version": 1},
  "profiles": {"available": ["local-default"], "default": "local-default"},
  "build": {
    "checkout_path": "$TMP_DIR/missing-checkout",
    "binary_path": "$BINARY",
    "checkout_dirty_at_rebuild": false
  },
  "upstream": {"commit": ""}
}
EOF_STATE

cat > "$PROFILES" <<EOF_PROFILES
{
  "bridge_contract_version": 1,
  "profiles": {
    "local-default": {
      "bridge_path": "$BRIDGE",
      "base_url": "http://localhost:8000",
      "config_path": "$CONFIG",
      "args": []
    }
  }
}
EOF_PROFILES

out=$(STATE_FILE="$STATE" PROFILE_STATE_FILE="$PROFILES" "$ROOT_DIR/install-stavrobot.sh" --print-shelley-mode-status --json)
python3 - <<'PY' "$out"
import json, sys
payload = json.loads(sys.argv[1])
assert payload['configured'] is True, payload
assert payload['enabled'] is True, payload
assert payload['mode'] == 'stavrobot', payload
assert payload['bridge_paths_ok'] is True, payload
assert payload['recorded_checkout_dirty_at_rebuild'] is False, payload
assert payload['recorded_checkout_dirty_at_rebuild_known'] is True, payload
print('install-stavrobot status-json tests passed')
PY

out_basic=$(STATE_FILE="$STATE" PROFILE_STATE_FILE="$PROFILES" "$ROOT_DIR/install-stavrobot.sh" --print-shelley-mode-status --basic)
if ! grep -Fq 'status:' <<<"$out_basic"; then
  printf 'expected basic status output to contain status line\n' >&2
  printf -- '--- output ---\n%s\n------------\n' "$out_basic" >&2
  exit 1
fi
