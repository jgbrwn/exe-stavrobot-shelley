#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

SHELLEY_DIR="${SHELLEY_DIR:-/opt/shelley}"
SHELLEY_BIN=""
PROFILE_STATE_PATH="${PROFILE_STATE_PATH:-$ROOT_DIR/state/shelley-bridge-profiles.json}"
BASE_PORT="8892"
DB_PREFIX="/tmp/shelley-managed-strict-raw-media-proof"
SESSION_PREFIX="shelley-managed-strict-raw-media-proof"

usage() {
  cat <<'USAGE'
Usage: ./run-shelley-managed-strict-raw-media-proof.sh [flags]

Runs the authoritative strict managed raw-media runtime proof matrix across deterministic fixtures.

Flags:
  --shelley-dir PATH         Shelley checkout dir (default: /opt/shelley)
  --shelley-bin PATH         Shelley binary path (default: SHELLEY_DIR/bin/shelley)
  --profile-state-path PATH  Bridge-profile state file (default: repo state path)
  --base-port PORT           Starting port for fixture matrix (default: 8892)
  --db-prefix PREFIX         DB path prefix for proof runs (default: /tmp/shelley-managed-strict-raw-media-proof)
  --session-prefix PREFIX    tmux session prefix for proof runs
  --help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shelley-dir)
      SHELLEY_DIR="$2"
      shift 2
      ;;
    --shelley-bin)
      SHELLEY_BIN="$2"
      shift 2
      ;;
    --profile-state-path)
      PROFILE_STATE_PATH="$2"
      shift 2
      ;;
    --base-port)
      BASE_PORT="$2"
      shift 2
      ;;
    --db-prefix)
      DB_PREFIX="$2"
      shift 2
      ;;
    --session-prefix)
      SESSION_PREFIX="$2"
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

require_cmd python3
[[ "$BASE_PORT" =~ ^[0-9]+$ ]] || die "--base-port must be numeric"
[[ -n "$SHELLEY_BIN" ]] || SHELLEY_BIN="$SHELLEY_DIR/bin/shelley"
[[ -x "$SHELLEY_BIN" ]] || die "Shelley binary not found or not executable: $SHELLEY_BIN"
[[ -f "$PROFILE_STATE_PATH" ]] || die "Profile state file not found: $PROFILE_STATE_PATH"

fixtures=(
  runtime_raw_media_only
  runtime_invalid_raw_media
  runtime_unsupported_raw_mime
  runtime_oversize_raw_media
)

declare -a passed=()

i=0
for fixture in "${fixtures[@]}"; do
  port=$((BASE_PORT + i))
  db_path="${DB_PREFIX}-${fixture}.db"
  session="${SESSION_PREFIX}-${fixture}"

  args=(
    --shelley-dir "$SHELLEY_DIR"
    --shelley-bin "$SHELLEY_BIN"
    --profile-state-path "$PROFILE_STATE_PATH"
    --port "$port"
    --db-path "$db_path"
    --tmux-session "$session"
    --bridge-fixture "$fixture"
  )

  case "$fixture" in
    runtime_raw_media_only)
      args+=(
        --expect-native-raw-media-gating
        --require-native-raw-media-hints
        --expect-media-refs
        --require-media-refs
      )
      ;;
    *)
      args+=(
        --expect-raw-media-rejection
        --require-raw-media-rejection-hints
      )
      ;;
  esac

  info "Strict proof fixture: $fixture (port=$port db=$db_path session=$session)"
  "$ROOT_DIR/smoke-test-shelley-managed-s1.sh" "${args[@]}"
  passed+=("$fixture:$port:$db_path")
  i=$((i + 1))
done

printf '\nstrict managed raw-media proof matrix passed\n'
for row in "${passed[@]}"; do
  IFS=':' read -r f p d <<<"$row"
  printf '  - %s port=%s db=%s\n' "$f" "$p" "$d"
done
