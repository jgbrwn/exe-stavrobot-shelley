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

if [[ ! -x "$ROOT_DIR/run-shelley-managed-s4-recall-validation.sh" ]]; then
  skip_or_fail "S4 recall validation helper missing or not executable"
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
if ! rg -q "SHELLEY_STAVROBOT_PROFILE_STATE_PATH" "$ROOT_DIR/run-shelley-managed-s4-recall-validation.sh"; then
  skip_or_fail "S4 runner does not yet inject profile-state override into isolated server process"
fi
if ! rg -q -- "--remote-isolation-profile-session" "$ROOT_DIR/run-shelley-managed-s4-recall-validation.sh"; then
  skip_or_fail "S4 runner does not yet expose deterministic remote isolation profile/session mode"
fi

out_json="/tmp/s4-runtime-contract.json"
"$ROOT_DIR/run-shelley-managed-s4-recall-validation.sh" \
  --shelley-dir "$SHELLEY_DIR" \
  --profile-state-path "$PROFILE_STATE_PATH" \
  --bridge-profile local-default \
  --port 8926 \
  --output-json "$out_json" \
  --require-remote-isolation \
  --remote-isolation-profile-session >/dev/null

python3 - "$out_json" <<'PY'
import json, os, sys
path = sys.argv[1]
report = json.load(open(path))
meta = report.get("metadata") or {}
softfail_policy = os.environ.get("S4_SOFTFAIL_POLICY", "allow")
raw_modes = {
    (p.get("raw") or {}).get("bridge_softfail")
    for p in (report.get("probes") or [])
    if isinstance(p, dict)
}
if meta.get("require_remote_isolation") is not True:
    raise SystemExit("require_remote_isolation must be true")
if meta.get("remote_isolation_profile_session") is not True:
    raise SystemExit("remote_isolation_profile_session must be true")
if meta.get("remote_isolation_ok") is not True and "context_overflow" not in raw_modes:
    raise SystemExit("remote_isolation_ok must be true unless context-overflow softfail evidence is present")
if softfail_policy == "strict" and "context_overflow" in raw_modes:
    raise SystemExit("strict S4 softfail policy forbids context-overflow softfail evidence")
seed = meta.get("seed_bridge_profiles") or {}
for key in ("A", "B", "C"):
    value = seed.get(key)
    if not isinstance(value, str) or "-s4-iso-" not in value:
        raise SystemExit(f"seed bridge profile missing/invalid for {key}")
remote_ids = meta.get("remote_stavrobot_conversation_ids") or []
if len(remote_ids) < 3:
    raise SystemExit("expected at least 3 distinct remote IDs")
for prefix in ("s4iso-a:", "s4iso-b:", "s4iso-c:"):
    if not any(isinstance(x, str) and x.startswith(prefix) for x in remote_ids):
        raise SystemExit(f"missing expected remote-id prefix: {prefix}")
PY

echo "s4 recall validation runtime contract tests passed"
