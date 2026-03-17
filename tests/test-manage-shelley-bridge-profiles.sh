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

BRIDGE="$TMP_DIR/bridge.sh"
CONFIG="$TMP_DIR/config.toml"
cat > "$BRIDGE" <<'EOF_BRIDGE'
#!/usr/bin/env bash
exit 0
EOF_BRIDGE
chmod +x "$BRIDGE"
printf 'provider = "openrouter"\n' > "$CONFIG"

STATE="$TMP_DIR/profiles.json"
cat > "$STATE" <<EOF_JSON
{
  "schema_version": 1,
  "bridge_contract_version": 1,
  "default_profile": "local-default",
  "profiles": {
    "local-default": {
      "enabled": true,
      "bridge_path": "$BRIDGE",
      "base_url": "http://localhost:8000",
      "config_path": "$CONFIG",
      "args": ["--stateless"],
      "notes": "test profile"
    }
  }
}
EOF_JSON

validate_out=$("$ROOT_DIR/manage-shelley-bridge-profiles.sh" validate --profile-state-path "$STATE")
assert_contains "$validate_out" '"status": "ok"'
assert_contains "$validate_out" '"default_profile": "local-default"'

resolve_out=$("$ROOT_DIR/manage-shelley-bridge-profiles.sh" resolve --profile-state-path "$STATE")
assert_contains "$resolve_out" '"status": "ok"'
assert_contains "$resolve_out" '"name": "local-default"'
assert_contains "$resolve_out" '"bridge_path": ' 
assert_contains "$resolve_out" '"args": ['

bad_state="$TMP_DIR/bad-profiles.json"
cp "$STATE" "$bad_state"
python3 - "$bad_state" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data['profiles']['local-default']['bridge_path'] = '/missing/bridge.sh'
open(p, 'w').write(json.dumps(data))
PY

bad_out=$("$ROOT_DIR/manage-shelley-bridge-profiles.sh" resolve --profile-state-path "$bad_state" 2>&1 || true)
assert_contains "$bad_out" '"status": "error"'
assert_contains "$bad_out" 'bridge_path_missing'

printf 'manage-shelley-bridge-profiles tests passed\n'
