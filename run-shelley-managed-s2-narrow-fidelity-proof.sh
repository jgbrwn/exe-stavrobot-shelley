#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

SHELLEY_DIR="${SHELLEY_DIR:-/opt/shelley}"
SHELLEY_BIN=""
PROFILE_STATE_PATH="${PROFILE_STATE_PATH:-$ROOT_DIR/state/shelley-bridge-profiles.json}"
BASE_PORT="8902"
DB_PREFIX="/tmp/shelley-managed-s2-narrow-fidelity-proof"
SESSION_PREFIX="shelley-managed-s2-narrow-fidelity-proof"

usage() {
  cat <<'USAGE'
Usage: ./run-shelley-managed-s2-narrow-fidelity-proof.sh [flags]

Runs the deterministic managed S2 narrow-fidelity fixture proof matrix.

Flags:
  --shelley-dir PATH         Shelley checkout dir (default: /opt/shelley)
  --shelley-bin PATH         Shelley binary path (default: SHELLEY_DIR/bin/shelley)
  --profile-state-path PATH  Bridge-profile state file (default: repo state path)
  --base-port PORT           Starting port for fixture matrix (default: 8902)
  --db-prefix PREFIX         DB path prefix for proof runs (default: /tmp/shelley-managed-s2-narrow-fidelity-proof)
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
  s2_markdown_tool_summary
  s2_markdown_media_refs
  s2_markdown_raw_tool_events
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
    s2_markdown_tool_summary)
      args+=(
        --expect-s2-markdown-tool-summary
        --require-s2-markdown-tool-summary-hints
      )
      ;;
    s2_markdown_media_refs)
      args+=(
        --expect-s2-markdown-media-refs
        --require-s2-markdown-media-refs-hints
      )
      ;;
    s2_markdown_raw_tool_events)
      args+=(
        --expect-s2-tool-summary-raw-fallback
        --require-s2-tool-summary-raw-fallback-hints
      )
      ;;
  esac

  info "S2 narrow-fidelity fixture: $fixture (port=$port db=$db_path session=$session)"
  "$ROOT_DIR/smoke-test-shelley-managed-s1.sh" "${args[@]}"
  passed+=("$fixture:$port:$db_path")
  i=$((i + 1))
done

printf '\nmanaged S2 narrow-fidelity fixture proof matrix passed\n'
for row in "${passed[@]}"; do
  IFS=':' read -r f p d <<<"$row"
  printf '  - %s port=%s db=%s\n' "$f" "$p" "$d"
done
