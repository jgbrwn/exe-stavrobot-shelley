#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

TEST_RUNNER="$ROOT_DIR/tests/run.sh"
REQUIRE_PATCHED_MANAGED_RUNTIME="${REQUIRE_PATCHED_MANAGED_RUNTIME:-0}"
RUN_FULL_SUITE=0
DRY_RUN=0
SHELLEY_DIR="${SHELLEY_DIR:-}"
PROFILE_STATE_PATH="${PROFILE_STATE_PATH:-}"
S4_SOFTFAIL_POLICY="${S4_SOFTFAIL_POLICY:-allow}"

usage() {
  cat <<'USAGE'
Usage: ./run-shelley-managed-memory-suitability-gate.sh [flags]

Runs the deterministic managed runtime suitability gate for memory-quality evidence.

Default lane runs these required-runtime contract tests in sequence:
  - test-shelley-managed-smoke-raw-media-runtime-contract.sh
  - test-shelley-managed-smoke-s2-narrow-fidelity-contract.sh
  - test-s4-recall-validation-runtime-contract.sh

Flags:
  --required-runtime         Set REQUIRE_PATCHED_MANAGED_RUNTIME=1 for fail-on-missing-prereqs behavior
  --shelley-dir PATH         Export SHELLEY_DIR for downstream test scripts
  --profile-state-path PATH  Export PROFILE_STATE_PATH for downstream test scripts
  --full-suite               After gate lane, run full helper/status suite (./tests/run.sh)
  --s4-softfail-policy MODE  MODE=allow|strict (default: allow)
                             strict: fail if S4 report contains context-overflow softfail evidence
  --dry-run                  Print planned commands only
  --help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --required-runtime)
      REQUIRE_PATCHED_MANAGED_RUNTIME=1
      shift
      ;;
    --shelley-dir)
      SHELLEY_DIR="$2"
      shift 2
      ;;
    --profile-state-path)
      PROFILE_STATE_PATH="$2"
      shift 2
      ;;
    --full-suite)
      RUN_FULL_SUITE=1
      shift
      ;;
    --s4-softfail-policy)
      S4_SOFTFAIL_POLICY="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

[[ -x "$TEST_RUNNER" ]] || die "Test runner missing or not executable: $TEST_RUNNER"
[[ "$S4_SOFTFAIL_POLICY" == "allow" || "$S4_SOFTFAIL_POLICY" == "strict" ]] || die "--s4-softfail-policy must be allow or strict"

if [[ -n "$SHELLEY_DIR" ]]; then
  export SHELLEY_DIR
fi
if [[ -n "$PROFILE_STATE_PATH" ]]; then
  export PROFILE_STATE_PATH
fi
export REQUIRE_PATCHED_MANAGED_RUNTIME
export S4_SOFTFAIL_POLICY

contract_tests=(
  test-shelley-managed-smoke-raw-media-runtime-contract.sh
  test-shelley-managed-smoke-s2-narrow-fidelity-contract.sh
  test-s4-recall-validation-runtime-contract.sh
)

run_cmd() {
  if (( DRY_RUN == 1 )); then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

info "Running managed memory suitability gate (required_runtime=$REQUIRE_PATCHED_MANAGED_RUNTIME)"
if [[ -n "${SHELLEY_DIR:-}" ]]; then
  info "SHELLEY_DIR=$SHELLEY_DIR"
fi
if [[ -n "${PROFILE_STATE_PATH:-}" ]]; then
  info "PROFILE_STATE_PATH=$PROFILE_STATE_PATH"
fi

for t in "${contract_tests[@]}"; do
  info "Gate lane test: $t"
  run_cmd "$TEST_RUNNER" "$t"
done

if (( RUN_FULL_SUITE == 1 )); then
  info "Running full helper/status suite"
  run_cmd "$TEST_RUNNER"
fi

info "Managed memory suitability gate passed"
