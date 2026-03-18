#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    printf 'expected output to contain: %s\n' "$needle" >&2
    printf -- '--- output ---\n%s\n------------\n' "$haystack" >&2
    exit 1
  fi
}

out=$("$ROOT_DIR/install-stavrobot.sh" --json 2>&1 || true)
assert_contains "$out" '--json currently requires --print-shelley-mode-status'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --json 2>&1 || true)
assert_contains "$out" '--json cannot be combined with --refresh-shelley-mode'

out=$("$ROOT_DIR/install-stavrobot.sh" --allow-dirty-shelley 2>&1 || true)
assert_contains "$out" '--allow-dirty-shelley, --skip-shelley-smoke, --expect-shelley-display-data, --require-shelley-display-hints, --expect-shelley-media-refs, --require-shelley-media-refs, and --shelley-bridge-fixture require --refresh-shelley-mode'

out=$("$ROOT_DIR/install-stavrobot.sh" --expect-shelley-display-data 2>&1 || true)
assert_contains "$out" '--allow-dirty-shelley, --skip-shelley-smoke, --expect-shelley-display-data, --require-shelley-display-hints, --expect-shelley-media-refs, --require-shelley-media-refs, and --shelley-bridge-fixture require --refresh-shelley-mode'

out=$("$ROOT_DIR/install-stavrobot.sh" --require-shelley-display-hints 2>&1 || true)
assert_contains "$out" '--allow-dirty-shelley, --skip-shelley-smoke, --expect-shelley-display-data, --require-shelley-display-hints, --expect-shelley-media-refs, --require-shelley-media-refs, and --shelley-bridge-fixture require --refresh-shelley-mode'

out=$("$ROOT_DIR/install-stavrobot.sh" --expect-shelley-media-refs 2>&1 || true)
assert_contains "$out" '--allow-dirty-shelley, --skip-shelley-smoke, --expect-shelley-display-data, --require-shelley-display-hints, --expect-shelley-media-refs, --require-shelley-media-refs, and --shelley-bridge-fixture require --refresh-shelley-mode'

out=$("$ROOT_DIR/install-stavrobot.sh" --require-shelley-media-refs 2>&1 || true)
assert_contains "$out" '--allow-dirty-shelley, --skip-shelley-smoke, --expect-shelley-display-data, --require-shelley-display-hints, --expect-shelley-media-refs, --require-shelley-media-refs, and --shelley-bridge-fixture require --refresh-shelley-mode'

out=$("$ROOT_DIR/install-stavrobot.sh" --shelley-bridge-fixture tool_summary 2>&1 || true)
assert_contains "$out" '--allow-dirty-shelley, --skip-shelley-smoke, --expect-shelley-display-data, --require-shelley-display-hints, --expect-shelley-media-refs, --require-shelley-media-refs, and --shelley-bridge-fixture require --refresh-shelley-mode'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --require-shelley-display-hints 2>&1 || true)
assert_contains "$out" '--require-shelley-display-hints requires --expect-shelley-display-data'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --expect-shelley-display-data --expect-shelley-media-refs --shelley-bridge-fixture tool_summary --skip-shelley-smoke --allow-dirty-shelley --stavrobot-dir /tmp/stavrobot 2>&1 || true)
assert_contains "$out" '--refresh-shelley-mode cannot be combined with --stavrobot-dir'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --require-shelley-media-refs 2>&1 || true)
assert_contains "$out" '--require-shelley-media-refs requires --expect-shelley-media-refs'

out=$("$ROOT_DIR/install-stavrobot.sh" --print-shelley-mode-status --refresh 2>&1 || true)
assert_contains "$out" '--print-shelley-mode-status cannot be combined with normal installer mutation flags'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --stavrobot-dir /tmp/stavrobot 2>&1 || true)
assert_contains "$out" '--refresh-shelley-mode cannot be combined with --stavrobot-dir'

printf 'install-stavrobot guardrail tests passed\n'
