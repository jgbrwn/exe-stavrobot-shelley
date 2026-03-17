#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

SHELLEY_DIR="${SHELLEY_DIR:-/opt/shelley}"
PROFILE_STATE_PATH="${PROFILE_STATE_PATH:-/var/lib/stavrobot-installer/shelley-bridge-profiles.json}"
PNPM_CMD="${PNPM_CMD:-npx --yes pnpm@10.28.0}"
STATE_FILE="$ROOT_DIR/state/shelley-mode-build.json"
RUN_SMOKE=1
ALLOW_DIRTY=0
SMOKE_PORT="8765"
SMOKE_DB_PATH="/tmp/shelley-stavrobot-managed-test.db"
SMOKE_TMUX_SESSION="shelley-managed-s1-smoke"
PATCH_DIR="$ROOT_DIR/patches/shelley/series"
PATCHES=(
  "$PATCH_DIR/0001-metadata-sql-ui.patch"
  "$PATCH_DIR/0002-conversation-manager.patch"
  "$PATCH_DIR/0003-route-branching.patch"
  "$PATCH_DIR/0004-stavrobot-runtime-unit.patch"
)
PATCH_SHAPE="s1-per-conversation-stavrobot"
PATCH_VERSION=1
BRIDGE_CONTRACT_VERSION=1

usage() {
  cat <<'EOF'
Usage: ./refresh-shelley-managed-s1.sh [flags]

Flags:
  --shelley-dir PATH           Managed Shelley checkout (default: /opt/shelley)
  --profile-state-path PATH    Managed bridge profile state file
  --pnpm-cmd CMD               Command used for pnpm operations
  --skip-smoke                 Skip isolated post-build smoke validation
  --allow-dirty                Allow running against a non-clean Shelley checkout
  --smoke-port PORT            Smoke-test port (default: 8765)
  --smoke-db-path PATH         Smoke-test sqlite db path
  --smoke-tmux-session NAME    Smoke-test tmux session name
  --help

Behavior:
  - applies the repo-owned 0001 -> 0004 Shelley patch series if not already applied
  - skips already-applied patches safely
  - rebuilds sqlc, UI assets, templates, and bin/shelley
  - optionally runs smoke-test-shelley-managed-s1.sh
  - writes state/shelley-mode-build.json with current managed rebuild provenance
EOF
}

write_state_file() {
  local upstream_repo upstream_branch upstream_commit upstream_short rebuilt_at profile_json
  upstream_repo=$(git -C "$SHELLEY_DIR" remote get-url origin)
  upstream_branch=$(git -C "$SHELLEY_DIR" symbolic-ref --short HEAD 2>/dev/null || printf 'detached')
  upstream_commit=$(git -C "$SHELLEY_DIR" rev-parse HEAD)
  upstream_short=$(git -C "$SHELLEY_DIR" rev-parse --short HEAD)
  rebuilt_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  profile_json=$(python3 - "$PROFILE_STATE_PATH" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
out = {
    'default': data.get('default_profile', ''),
    'available': sorted((data.get('profiles') or {}).keys()),
    'bridge_contract_version': data.get('bridge_contract_version', 0),
}
print(json.dumps(out))
PY
)
  python3 - "$STATE_FILE" "$upstream_repo" "$upstream_branch" "$upstream_commit" "$upstream_short" "$SHELLEY_DIR" "$SHELLEY_DIR/bin/shelley" "$rebuilt_at" "$PATCH_SHAPE" "$PATCH_VERSION" "$profile_json" <<'PY'
import json, os, sys
(state_file, repo, branch, commit, commit_short, checkout_path, binary_path,
 rebuilt_at, patch_shape, patch_version, profile_json) = sys.argv[1:12]
profile = json.loads(profile_json)
out = {
    'schema_version': 1,
    'mode': 'stavrobot',
    'enabled': True,
    'managed_at': rebuilt_at,
    'upstream': {
        'repo': repo,
        'branch': branch,
        'commit': commit,
        'commit_short': commit_short,
    },
    'local_contract': {
        'patch_shape': patch_shape,
        'patch_version': int(patch_version),
        'bridge_contract_version': int(profile.get('bridge_contract_version', 0)),
    },
    'build': {
        'checkout_path': checkout_path,
        'binary_path': binary_path,
        'ui_built': True,
        'templates_built': True,
        'rebuilt_at': rebuilt_at,
    },
    'profiles': {
        'default': profile.get('default', ''),
        'available': profile.get('available', []),
    },
    'status': {
        'upstream_stale': False,
        'profiles_stale': False,
        'rebuild_required': False,
        'last_check_at': rebuilt_at,
    },
}
os.makedirs(os.path.dirname(state_file), exist_ok=True)
with open(state_file, 'w') as f:
    json.dump(out, f, indent=2, sort_keys=True)
    f.write('\n')
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shelley-dir)
      SHELLEY_DIR="$2"
      shift 2
      ;;
    --profile-state-path)
      PROFILE_STATE_PATH="$2"
      shift 2
      ;;
    --pnpm-cmd)
      PNPM_CMD="$2"
      shift 2
      ;;
    --skip-smoke)
      RUN_SMOKE=0
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --smoke-port)
      SMOKE_PORT="$2"
      shift 2
      ;;
    --smoke-db-path)
      SMOKE_DB_PATH="$2"
      shift 2
      ;;
    --smoke-tmux-session)
      SMOKE_TMUX_SESSION="$2"
      shift 2
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

require_cmd git
require_cmd go
require_cmd make
require_cmd node
require_cmd npx
require_cmd python3
[[ -d "$SHELLEY_DIR/.git" ]] || die "Shelley checkout is not a git repo: $SHELLEY_DIR"
[[ -f "$PROFILE_STATE_PATH" ]] || die "Profile state file not found: $PROFILE_STATE_PATH"
python3 "$ROOT_DIR/py/shelley_bridge_profiles.py" validate "$PROFILE_STATE_PATH" >/dev/null

if (( ALLOW_DIRTY == 0 )) && [[ -n "$(git -C "$SHELLEY_DIR" status --porcelain)" ]]; then
  die "Shelley checkout is not clean: $SHELLEY_DIR (use --allow-dirty if this is intentional)"
fi

for patch in "${PATCHES[@]}"; do
  base=$(basename "$patch")
  if git -C "$SHELLEY_DIR" apply --check "$patch" >/dev/null 2>&1; then
    info "Applying $base"
    git -C "$SHELLEY_DIR" apply "$patch"
  elif git -C "$SHELLEY_DIR" apply --reverse --check "$patch" >/dev/null 2>&1; then
    info "Skipping already-applied $base"
  else
    die "Patch is neither cleanly applicable nor already applied: $base"
  fi
done

info "Regenerating sqlc output"
(cd "$SHELLEY_DIR" && go tool github.com/sqlc-dev/sqlc/cmd/sqlc generate -f sqlc.yaml)

info "Installing UI dependencies"
(cd "$SHELLEY_DIR/ui" && eval "$PNPM_CMD install --frozen-lockfile")

info "Building UI assets"
(cd "$SHELLEY_DIR/ui" && eval "$PNPM_CMD run build")

info "Building templates"
(cd "$SHELLEY_DIR" && make templates)

info "Building Shelley binary"
(cd "$SHELLEY_DIR" && go build -o bin/shelley ./cmd/shelley)

if (( RUN_SMOKE == 1 )); then
  info "Running isolated managed Shelley smoke test"
  "$ROOT_DIR/smoke-test-shelley-managed-s1.sh" \
    --shelley-dir "$SHELLEY_DIR" \
    --shelley-bin "$SHELLEY_DIR/bin/shelley" \
    --profile-state-path "$PROFILE_STATE_PATH" \
    --port "$SMOKE_PORT" \
    --db-path "$SMOKE_DB_PATH" \
    --tmux-session "$SMOKE_TMUX_SESSION"
fi

write_state_file
info "Wrote rebuild state: $STATE_FILE"

# Notes:
# - this helper is intentionally conservative: it refuses a dirty checkout unless --allow-dirty is given
# - already-applied patches are detected via reverse apply checks so reruns can be idempotent enough for local managed refreshes
