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

out=$("$ROOT_DIR/install-stavrobot.sh" --basic 2>&1 || true)
assert_contains "$out" '--basic currently requires --print-shelley-mode-status'

out=$("$ROOT_DIR/install-stavrobot.sh" --print-shelley-mode-status --json --basic 2>&1 || true)
assert_contains "$out" '--json cannot be combined with --basic'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --json 2>&1 || true)
assert_contains "$out" '--json cannot be combined with --refresh-shelley-mode'

refresh_only_err='--allow-dirty-shelley, --skip-shelley-smoke, --expect-shelley-display-data, --require-shelley-display-hints, --expect-shelley-media-refs, --require-shelley-media-refs, --expect-shelley-native-raw-media-gating, --require-shelley-native-raw-media-hints, --expect-shelley-raw-media-rejection, --require-shelley-raw-media-rejection-hints, --expect-shelley-s2-markdown-tool-summary, --require-shelley-s2-markdown-tool-summary-hints, --expect-shelley-s2-markdown-media-refs, --require-shelley-s2-markdown-media-refs-hints, --expect-shelley-s2-tool-summary-raw-fallback, --require-shelley-s2-tool-summary-raw-fallback-hints, --strict-shelley-raw-media-profile, --s2-shelley-narrow-fidelity-profile, --memory-suitability-gate-shelley-profile, --sync-shelley-upstream-ff-only, and --shelley-bridge-fixture require --refresh-shelley-mode'

out=$("$ROOT_DIR/install-stavrobot.sh" --allow-dirty-shelley 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --expect-shelley-display-data 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --require-shelley-display-hints 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --expect-shelley-media-refs 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --require-shelley-media-refs 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --expect-shelley-native-raw-media-gating 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --require-shelley-native-raw-media-hints 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --expect-shelley-raw-media-rejection 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --require-shelley-raw-media-rejection-hints 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --expect-shelley-s2-markdown-tool-summary 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --require-shelley-s2-markdown-tool-summary-hints 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --expect-shelley-s2-markdown-media-refs 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --require-shelley-s2-markdown-media-refs-hints 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --expect-shelley-s2-tool-summary-raw-fallback 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --require-shelley-s2-tool-summary-raw-fallback-hints 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --shelley-bridge-fixture tool_summary 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --strict-shelley-raw-media-profile 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --s2-shelley-narrow-fidelity-profile 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --memory-suitability-gate-shelley-profile 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --sync-shelley-upstream-ff-only 2>&1 || true)
assert_contains "$out" "$refresh_only_err"

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --require-shelley-display-hints 2>&1 || true)
assert_contains "$out" '--require-shelley-display-hints requires --expect-shelley-display-data'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --expect-shelley-display-data --expect-shelley-media-refs --expect-shelley-native-raw-media-gating --expect-shelley-raw-media-rejection --shelley-bridge-fixture tool_summary --skip-shelley-smoke --allow-dirty-shelley --stavrobot-dir /tmp/stavrobot 2>&1 || true)
assert_contains "$out" '--refresh-shelley-mode cannot be combined with --stavrobot-dir'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --require-shelley-media-refs 2>&1 || true)
assert_contains "$out" '--require-shelley-media-refs requires --expect-shelley-media-refs'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --require-shelley-native-raw-media-hints 2>&1 || true)
assert_contains "$out" '--require-shelley-native-raw-media-hints requires --expect-shelley-native-raw-media-gating'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --require-shelley-raw-media-rejection-hints 2>&1 || true)
assert_contains "$out" '--require-shelley-raw-media-rejection-hints requires --expect-shelley-raw-media-rejection'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --require-shelley-s2-markdown-tool-summary-hints 2>&1 || true)
assert_contains "$out" '--require-shelley-s2-markdown-tool-summary-hints requires --expect-shelley-s2-markdown-tool-summary'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --require-shelley-s2-markdown-media-refs-hints 2>&1 || true)
assert_contains "$out" '--require-shelley-s2-markdown-media-refs-hints requires --expect-shelley-s2-markdown-media-refs'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --require-shelley-s2-tool-summary-raw-fallback-hints 2>&1 || true)
assert_contains "$out" '--require-shelley-s2-tool-summary-raw-fallback-hints requires --expect-shelley-s2-tool-summary-raw-fallback'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --strict-shelley-raw-media-profile --expect-shelley-raw-media-rejection 2>&1 || true)
assert_contains "$out" '--strict-shelley-raw-media-profile cannot be combined with explicit --expect/--require Shelley smoke flags or --shelley-bridge-fixture'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --s2-shelley-narrow-fidelity-profile --expect-shelley-s2-markdown-media-refs 2>&1 || true)
assert_contains "$out" '--s2-shelley-narrow-fidelity-profile cannot be combined with explicit --expect/--require Shelley smoke flags or --shelley-bridge-fixture'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --s2-shelley-narrow-fidelity-profile --strict-shelley-raw-media-profile 2>&1 || true)
assert_contains "$out" '--strict-shelley-raw-media-profile cannot be combined with --s2-shelley-narrow-fidelity-profile'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --memory-suitability-gate-shelley-profile --expect-shelley-media-refs 2>&1 || true)
assert_contains "$out" '--memory-suitability-gate-shelley-profile cannot be combined with explicit --expect/--require Shelley smoke flags or --shelley-bridge-fixture'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --memory-suitability-gate-shelley-profile --strict-shelley-raw-media-profile 2>&1 || true)
assert_contains "$out" '--memory-suitability-gate-shelley-profile cannot be combined with --strict-shelley-raw-media-profile'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --memory-suitability-gate-shelley-profile --s2-shelley-narrow-fidelity-profile 2>&1 || true)
assert_contains "$out" '--memory-suitability-gate-shelley-profile cannot be combined with --s2-shelley-narrow-fidelity-profile'

out=$("$ROOT_DIR/install-stavrobot.sh" --print-shelley-mode-status --refresh 2>&1 || true)
assert_contains "$out" '--print-shelley-mode-status cannot be combined with normal installer mutation flags'

out=$("$ROOT_DIR/install-stavrobot.sh" --refresh-shelley-mode --stavrobot-dir /tmp/stavrobot 2>&1 || true)
assert_contains "$out" '--refresh-shelley-mode cannot be combined with --stavrobot-dir'

printf 'install-stavrobot guardrail tests passed\n'

out=$("$ROOT_DIR/refresh-shelley-managed-s1.sh" --help 2>&1)
assert_contains "$out" '--smoke-port PORT            Smoke-test port (default: 8765; must not be 9999, reserved for operator/dev Shelley)'

out=$("$ROOT_DIR/smoke-test-shelley-managed-s1.sh" --help 2>&1)
assert_contains "$out" '--port PORT                    Test port (default: 8765; must not be 9999, reserved for operator/dev Shelley)'

out=$("$ROOT_DIR/smoke-test-shelley-managed-s1.sh" --port 9999 2>&1 || true)
assert_contains "$out" '--port 9999 is reserved for operator/dev Shelley; choose a dedicated smoke port'

out=$("$ROOT_DIR/refresh-shelley-managed-s1.sh" --skip-smoke --smoke-port 9999 2>&1 || true)
assert_contains "$out" '--smoke-port 9999 is reserved for operator/dev Shelley; choose a dedicated smoke port'

out=$("$ROOT_DIR/refresh-shelley-managed-s1.sh" --smoke-memory-suitability-gate-profile --smoke-bridge-fixture tool_summary 2>&1 || true)
assert_contains "$out" '--smoke-memory-suitability-gate-profile cannot be combined with explicit smoke expectation flags or --smoke-bridge-fixture'

out=$("$ROOT_DIR/refresh-shelley-managed-s1.sh" --smoke-memory-suitability-gate-profile --smoke-strict-raw-media-profile 2>&1 || true)
assert_contains "$out" '--smoke-memory-suitability-gate-profile cannot be combined with --smoke-strict-raw-media-profile'

out=$("$ROOT_DIR/refresh-shelley-managed-s1.sh" --smoke-memory-suitability-gate-profile --smoke-s2-narrow-fidelity-profile 2>&1 || true)
assert_contains "$out" '--smoke-memory-suitability-gate-profile cannot be combined with --smoke-s2-narrow-fidelity-profile'

out=$("$ROOT_DIR/install-stavrobot.sh" --doctor --refresh-shelley-mode 2>&1 || true)
assert_contains "$out" '--doctor cannot be combined with installer mutation or Shelley refresh/status flags'

out=$("$ROOT_DIR/install-stavrobot.sh" --deploy-cloudflare-email-worker 2>&1 || true)
assert_contains "$out" '--deploy-cloudflare-email-worker, --cloudflare-worker-name, and --cloudflare-account-id require --configure-cloudflare-email-worker'

out=$("$ROOT_DIR/install-stavrobot.sh" --cloudflare-worker-name foo 2>&1 || true)
assert_contains "$out" '--deploy-cloudflare-email-worker, --cloudflare-worker-name, and --cloudflare-account-id require --configure-cloudflare-email-worker'

out=$("$ROOT_DIR/install-stavrobot.sh" --configure-cloudflare-email-worker --refresh-shelley-mode --stavrobot-dir /tmp/stavrobot 2>&1 || true)
assert_contains "$out" '--configure-cloudflare-email-worker cannot be combined with --refresh-shelley-mode'

out=$("$ROOT_DIR/install-stavrobot.sh" --disable-exedev-email-bridge 2>&1 || true)
assert_contains "$out" '--disable-exedev-email-bridge requires --configure-exedev-email-bridge'

out=$("$ROOT_DIR/install-stavrobot.sh" --configure-exedev-email-bridge --refresh-shelley-mode --stavrobot-dir /tmp/stavrobot 2>&1 || true)
assert_contains "$out" '--configure-exedev-email-bridge cannot be combined with --refresh-shelley-mode'

out=$("$ROOT_DIR/install-stavrobot.sh" --configure-cloudflare-email-worker --configure-exedev-email-bridge --stavrobot-dir /tmp/stavrobot 2>&1 || true)
assert_contains "$out" '--configure-cloudflare-email-worker cannot be combined with --configure-exedev-email-bridge'

out=$("$ROOT_DIR/install-stavrobot.sh" --email-smtp-host smtp.example.com 2>&1 || true)
assert_contains "$out" '--email-mode is required when using non-interactive --email-* overrides'

out=$("$ROOT_DIR/install-stavrobot.sh" --email-mode not-a-mode --email-webhook-secret s 2>&1 || true)
assert_contains "$out" '--email-mode must be one of: smtp, exedev-relay, inbound-only'

out=$("$ROOT_DIR/install-stavrobot.sh" --doctor --email-mode smtp 2>&1 || true)
assert_contains "$out" '--doctor cannot be combined with installer mutation or Shelley refresh/status flags'
