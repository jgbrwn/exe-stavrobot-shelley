#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

STATE_FILE="${STATE_FILE:-$ROOT_DIR/state/shelley-mode-build.json}"
PROFILE_STATE_FILE="${PROFILE_STATE_FILE:-$ROOT_DIR/state/shelley-bridge-profiles.json}"
SHELLEY_DIR_OVERRIDE=""
JSON=0

usage() {
  cat <<'EOF'
Usage: ./print-shelley-managed-status.sh [flags]

Flags:
  --state-file PATH           Managed Shelley rebuild state file
  --profile-state-file PATH   Bridge profile state file
  --shelley-dir PATH          Override Shelley checkout path instead of using state file value
  --json                      Print computed status JSON
  --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file)
      STATE_FILE="$2"
      shift 2
      ;;
    --profile-state-file)
      PROFILE_STATE_FILE="$2"
      shift 2
      ;;
    --shelley-dir)
      SHELLEY_DIR_OVERRIDE="$2"
      shift 2
      ;;
    --json)
      JSON=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

require_cmd python3
require_cmd git

python3 - "$STATE_FILE" "$PROFILE_STATE_FILE" "$SHELLEY_DIR_OVERRIDE" "$JSON" <<'PY'
import json, os, subprocess, sys
from pathlib import Path

state_file, profile_file, shelley_dir_override, json_mode = sys.argv[1:5]
json_mode = json_mode == '1'

result = {
    'configured': False,
    'state_file': state_file,
    'profile_state_file': profile_file,
    'enabled': False,
    'mode': '',
    'checkout_path': '',
    'binary_path': '',
    'recorded_upstream_commit': '',
    'current_checkout_commit': '',
    'upstream_current': 'unknown',
    'profiles_current': 'unknown',
    'profiles_missing': [],
    'bridge_paths_ok': True,
    'checkout_exists': False,
    'binary_exists': False,
    'rebuild_required': True,
    'notes': [],
}

state = None
profiles = None
if Path(state_file).exists():
    try:
        state = json.loads(Path(state_file).read_text())
        result['configured'] = True
        result['enabled'] = bool(state.get('enabled'))
        result['mode'] = state.get('mode', '')
        result['checkout_path'] = shelley_dir_override or ((state.get('build') or {}).get('checkout_path', ''))
        result['binary_path'] = ((state.get('build') or {}).get('binary_path', ''))
        result['recorded_upstream_commit'] = ((state.get('upstream') or {}).get('commit', ''))
    except Exception as e:
        result['notes'].append(f'state file unreadable: {e}')
else:
    result['notes'].append('state file missing')

if Path(profile_file).exists():
    try:
        profiles = json.loads(Path(profile_file).read_text())
    except Exception as e:
        result['notes'].append(f'profile state unreadable: {e}')
else:
    result['notes'].append('profile state file missing')

if result['checkout_path']:
    result['checkout_exists'] = Path(result['checkout_path']).joinpath('.git').exists()
    if result['checkout_exists']:
        try:
            result['current_checkout_commit'] = subprocess.check_output(
                ['git', '-C', result['checkout_path'], 'rev-parse', 'HEAD'],
                text=True,
            ).strip()
        except Exception as e:
            result['notes'].append(f'failed to read checkout commit: {e}')

if result['binary_path']:
    result['binary_exists'] = Path(result['binary_path']).exists()

if result['recorded_upstream_commit'] and result['current_checkout_commit']:
    result['upstream_current'] = 'current' if result['recorded_upstream_commit'] == result['current_checkout_commit'] else 'stale'

if state and profiles:
    recorded = set(((state.get('profiles') or {}).get('available') or []))
    current = set((profiles.get('profiles') or {}).keys())
    missing = sorted(recorded - current)
    result['profiles_missing'] = missing
    contract_match = ((state.get('local_contract') or {}).get('bridge_contract_version') == profiles.get('bridge_contract_version'))
    if not contract_match:
        result['notes'].append('bridge contract version mismatch')
    default_profile = (state.get('profiles') or {}).get('default', '')
    if default_profile and default_profile not in current:
        missing.append(default_profile)
    result['profiles_current'] = 'current' if (not missing and contract_match) else 'stale'

    for name, profile in (profiles.get('profiles') or {}).items():
        bridge_path = profile.get('bridge_path', '')
        if bridge_path and not (Path(bridge_path).exists() and os.access(bridge_path, os.X_OK)):
            result['bridge_paths_ok'] = False
            result['notes'].append(f'bridge path missing or not executable: {name} -> {bridge_path}')

rebuild_required = False
if not result['configured'] or not result['enabled']:
    rebuild_required = True
elif not result['checkout_exists'] or not result['binary_exists']:
    rebuild_required = True
elif result['upstream_current'] == 'stale' or result['profiles_current'] == 'stale' or not result['bridge_paths_ok']:
    rebuild_required = True

result['rebuild_required'] = rebuild_required

if json_mode:
    print(json.dumps(result, indent=2, sort_keys=True))
    raise SystemExit(0)

print(f"configured: {'yes' if result['configured'] else 'no'}")
print(f"enabled: {'yes' if result['enabled'] else 'no'}")
if result['mode']:
    print(f"mode: {result['mode']}")
if result['checkout_path']:
    print(f"checkout_path: {result['checkout_path']} ({'present' if result['checkout_exists'] else 'missing'})")
if result['binary_path']:
    print(f"binary_path: {result['binary_path']} ({'present' if result['binary_exists'] else 'missing'})")
if result['recorded_upstream_commit']:
    print(f"recorded_upstream_commit: {result['recorded_upstream_commit']}")
if result['current_checkout_commit']:
    print(f"current_checkout_commit: {result['current_checkout_commit']}")
print(f"upstream_status: {result['upstream_current']}")
print(f"profiles_status: {result['profiles_current']}")
if result['profiles_missing']:
    print(f"profiles_missing: {', '.join(sorted(set(result['profiles_missing'])))}")
print(f"bridge_paths_ok: {'yes' if result['bridge_paths_ok'] else 'no'}")
print(f"rebuild_required: {'yes' if result['rebuild_required'] else 'no'}")
if result['notes']:
    print('notes:')
    for note in result['notes']:
        print(f"  - {note}")
PY
