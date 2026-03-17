#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR="$ROOT_DIR/tests"

usage() {
  cat <<'USAGE'
Usage: ./tests/run.sh [test-name ...]

Run lightweight repo-owned helper/status tests.

Examples:
  ./tests/run.sh
  ./tests/run.sh test-print-shelley-managed-status.sh
USAGE
}

if [[ ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  tests=("$@")
else
  mapfile -t tests < <(find "$TEST_DIR" -maxdepth 1 -type f -name 'test-*.sh' -printf '%f\n' | sort)
fi

if [[ ${#tests[@]} -eq 0 ]]; then
  echo "No tests found under $TEST_DIR" >&2
  exit 1
fi

for test_name in "${tests[@]}"; do
  test_path="$TEST_DIR/$test_name"
  if [[ ! -f "$test_path" ]]; then
    echo "Unknown test: $test_name" >&2
    exit 1
  fi
  echo "==> $test_name"
  "$test_path"
  echo
done

echo "All helper/status tests passed"
