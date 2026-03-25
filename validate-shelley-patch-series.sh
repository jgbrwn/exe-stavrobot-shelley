#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

UPSTREAM_CHECKOUT="${UPSTREAM_CHECKOUT:-/tmp/shelley-official}"
UPSTREAM_REF="${UPSTREAM_REF:-HEAD}"
WORKTREE_DIR=""
KEEP_WORKTREE=0
RUN_UI_BUILD=1
RUN_GO_TESTS=1
PNPM_CMD="${PNPM_CMD:-npx --yes pnpm@10.28.0}"
PATCH_DIR="$ROOT_DIR/patches/shelley/series"
PATCHES=(
  "$PATCH_DIR/0001-metadata-sql-ui.patch"
  "$PATCH_DIR/0002-conversation-manager.patch"
  "$PATCH_DIR/0003-route-branching.patch"
  "$PATCH_DIR/0004-stavrobot-runtime-unit.patch"
  "$PATCH_DIR/0005-stavrobot-model-control-readonly-picker.patch"
  "$PATCH_DIR/0006-stavrobot-model-control-apply-picker.patch"
  "$PATCH_DIR/0007-stavrobot-model-control-apply-safety-copy.patch"
  "$PATCH_DIR/0008-stavrobot-model-control-tests-and-contract.patch"
)

usage() {
  cat <<'EOF'
Usage: ./validate-shelley-patch-series.sh [flags]

Flags:
  --upstream-checkout PATH   Upstream Shelley git checkout (default: /tmp/shelley-official)
  --upstream-ref REF         Commit/ref to validate against (default: HEAD)
  --worktree-dir PATH        Explicit temporary worktree path (default: mktemp)
  --keep-worktree            Leave validation worktree on disk after success/failure
  --skip-ui-build            Skip UI dependency install/build step
  --skip-go-tests            Skip Go test step
  --pnpm-cmd CMD             Command used for pnpm operations
  --help

Behavior:
  - creates a detached git worktree from the upstream checkout
  - runs git apply --check for 0001 -> 0004
  - applies the patches in sequence
  - optionally builds ui/dist using pnpm
  - optionally runs go test ./server/... ./db/...
EOF
}

cleanup() {
  if [[ -n "$WORKTREE_DIR" && $KEEP_WORKTREE -eq 0 && -d "$WORKTREE_DIR" ]]; then
    git -C "$UPSTREAM_CHECKOUT" worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1 || rm -rf "$WORKTREE_DIR"
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upstream-checkout)
      UPSTREAM_CHECKOUT="$2"
      shift 2
      ;;
    --upstream-ref)
      UPSTREAM_REF="$2"
      shift 2
      ;;
    --worktree-dir)
      WORKTREE_DIR="$2"
      shift 2
      ;;
    --keep-worktree)
      KEEP_WORKTREE=1
      shift
      ;;
    --skip-ui-build)
      RUN_UI_BUILD=0
      shift
      ;;
    --skip-go-tests)
      RUN_GO_TESTS=0
      shift
      ;;
    --pnpm-cmd)
      PNPM_CMD="$2"
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
require_cmd node
require_cmd npx
[[ -d "$UPSTREAM_CHECKOUT/.git" ]] || die "Upstream checkout is not a git repo: $UPSTREAM_CHECKOUT"
for patch in "${PATCHES[@]}"; do
  [[ -f "$patch" ]] || die "Missing patch artifact: $patch"
done

resolved_ref=$(git -C "$UPSTREAM_CHECKOUT" rev-parse "$UPSTREAM_REF")
short_ref=$(git -C "$UPSTREAM_CHECKOUT" rev-parse --short "$resolved_ref")
if [[ -z "$WORKTREE_DIR" ]]; then
  WORKTREE_DIR=$(mktemp -d /tmp/shelley-patch-series-validate-XXXXXX)
else
  rm -rf "$WORKTREE_DIR"
  mkdir -p "$WORKTREE_DIR"
fi
rmdir "$WORKTREE_DIR"

git -C "$UPSTREAM_CHECKOUT" worktree add --detach "$WORKTREE_DIR" "$resolved_ref" >/dev/null
info "Validation worktree: $WORKTREE_DIR"
info "Upstream ref: $resolved_ref ($short_ref)"

for patch in "${PATCHES[@]}"; do
  base=$(basename "$patch")
  info "Checking $base"
  git -C "$WORKTREE_DIR" apply --check "$patch"
  info "Applying $base"
  git -C "$WORKTREE_DIR" apply "$patch"
done

info "Applied patch series cleanly"
git -C "$WORKTREE_DIR" diff --stat

if (( RUN_UI_BUILD == 1 )); then
  info "Installing UI dependencies"
  (cd "$WORKTREE_DIR/ui" && eval "$PNPM_CMD install --frozen-lockfile")
  info "Building UI assets"
  (cd "$WORKTREE_DIR/ui" && eval "$PNPM_CMD run build")
fi

if (( RUN_GO_TESTS == 1 )); then
  info "Running Go tests"
  (cd "$WORKTREE_DIR" && go test ./server/... ./db/...)
fi

info "Shelley patch series validation passed"
if (( KEEP_WORKTREE == 1 )); then
  info "Kept worktree: $WORKTREE_DIR"
fi

# Notes:
# - upstream Shelley server tests require ui/dist to exist because ui/embedfs.go embeds dist/*
# - default pnpm command uses npx so the validator works even when pnpm is not preinstalled globally
