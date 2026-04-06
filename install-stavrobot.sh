#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/repo.sh"
source "$ROOT_DIR/lib/prompts.sh"
source "$ROOT_DIR/lib/docker.sh"
source "$ROOT_DIR/lib/stavrobot_api.sh"
source "$ROOT_DIR/lib/summary.sh"

STAVROBOT_DIR=""
REFRESH_ONLY=0
PLUGINS_ONLY=0
CONFIG_ONLY=0
SKIP_CONFIG=0
SKIP_PLUGINS=0
SHOW_SECRETS=0
SHELLEY_STATUS_ONLY=0
SHELLEY_STATUS_JSON=0
SHELLEY_STATUS_BASIC=0
SHELLEY_REFRESH_ONLY=0
SHELLEY_ALLOW_DIRTY=0
SHELLEY_SKIP_SMOKE=0
SHELLEY_EXPECT_DISPLAY_DATA=0
SHELLEY_REQUIRE_DISPLAY_HINTS=0
SHELLEY_EXPECT_MEDIA_REFS=0
SHELLEY_REQUIRE_MEDIA_REFS=0
SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING=0
SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS=0
SHELLEY_EXPECT_RAW_MEDIA_REJECTION=0
SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS=0
SHELLEY_EXPECT_S2_MARKDOWN_TOOL_SUMMARY=0
SHELLEY_REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS=0
SHELLEY_EXPECT_S2_MARKDOWN_MEDIA_REFS=0
SHELLEY_REQUIRE_S2_MARKDOWN_MEDIA_REFS_HINTS=0
SHELLEY_EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK=0
SHELLEY_REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS=0
SHELLEY_BRIDGE_FIXTURE=""
SHELLEY_STRICT_RAW_MEDIA_PROFILE=0
SHELLEY_S2_NARROW_FIDELITY_PROFILE=0
SHELLEY_MEMORY_SUITABILITY_GATE_PROFILE=0
SHELLEY_SYNC_UPSTREAM_FF_ONLY=0
SHELLEY_REFRESH_BASIC=0
SHELLEY_REFRESH_RELEASE=0
DOCTOR_ONLY=0
DOCTOR_JSON=0
CF_EMAIL_WORKER_ONLY=0
CF_EMAIL_WORKER_DEPLOY=0
CF_EMAIL_WORKER_NAME=""
CF_EMAIL_WORKER_ACCOUNT_ID=""
EXEDEV_EMAIL_BRIDGE_ONLY=0
EXEDEV_EMAIL_BRIDGE_DISABLE=0
EMAIL_MODE_OVERRIDE=""
EMAIL_WEBHOOK_SECRET_OVERRIDE=""
EMAIL_OWNER_OVERRIDE=""
EMAIL_SMTP_HOST_OVERRIDE=""
EMAIL_SMTP_PORT_OVERRIDE=""
EMAIL_SMTP_USER_OVERRIDE=""
EMAIL_SMTP_PASSWORD_OVERRIDE=""
EMAIL_FROM_OVERRIDE=""
PRIVATE_MODAL_ENABLE=0
PRIVATE_MODAL_DISABLE=0
PRIVATE_MODAL_SET_DEFAULT=0
PRIVATE_MODAL_DEPLOY=0
PRIVATE_MODAL_SKIP_PREFETCH=0
PRIVATE_MODAL_APP_NAME_OVERRIDE=""
PRIVATE_MODAL_UPSTREAM_URL_OVERRIDE=""
PRIVATE_MODAL_TOKEN_ID_OVERRIDE=""
PRIVATE_MODAL_TOKEN_SECRET_OVERRIDE=""
PRIVATE_MODAL_PROXY_TOKEN_ID_OVERRIDE=""
PRIVATE_MODAL_PROXY_TOKEN_SECRET_OVERRIDE=""
PRIVATE_MODAL_MODEL_OVERRIDE=""
PRIVATE_MODAL_HF_MODEL_ID_OVERRIDE=""
PRIVATE_MODAL_CONTEXT_WINDOW_OVERRIDE=""
PRIVATE_MODAL_MAX_TOKENS_OVERRIDE=""
PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE=""
MANAGED_SHELLEY_DIR="${MANAGED_SHELLEY_DIR:-${SHELLEY_DIR:-/opt/shelley}}"
STAVROBOT_REPO_URL="${STAVROBOT_REPO_URL:-https://github.com/skorokithakis/stavrobot.git}"
STAVROBOT_BASE_URL="${STAVROBOT_BASE_URL:-http://localhost:8000}"

ENV_PATH=""
CONFIG_PATH=""
PLUGIN_STATE_JSON=""
OPENROUTER_OUT=""
CURRENT_JSON=""
PASSWORD_FOR_READY=""
PUBLIC_HOSTNAME_FINAL="[unchanged]"
AUTH_MODE_FINAL="apiKey"
CODER_ENABLED=false
SIGNAL_ENABLED=false
WHATSAPP_ENABLED=false
EMAIL_ENABLED=false
EMAIL_TRANSPORT_MODE="smtp"
PLUGINS_SELECTED_COUNT=0
PLUGINS_HANDLED=0
PLUGIN_REPORT_FILE=""

usage_basic() {
  cat <<'EOF'
Usage (most users):

  # 0) Preflight doctor (safe/read-only)
  ./install-stavrobot.sh --doctor

  # 1) First install / setup
  ./install-stavrobot.sh --stavrobot-dir /opt/stavrobot

  # 2) Later: refresh Stavrobot to latest upstream and rebuild if needed
  ./install-stavrobot.sh --stavrobot-dir /opt/stavrobot --refresh

  # 3) Optional: refresh managed Shelley mode from upstream + reapply patch + strict proof
  ./install-stavrobot.sh --refresh-shelley-mode-basic

  # 4) Optional: refresh managed Shelley mode + required-runtime memory suitability gate
  ./install-stavrobot.sh --refresh-shelley-mode-release

  # 5) Optional: Cloudflare email worker bundle/deploy helper
  ./install-stavrobot.sh --configure-cloudflare-email-worker --stavrobot-dir /opt/stavrobot

  # 6) Optional: exe.dev inbound email bridge helper (alternative to Cloudflare)
  ./install-stavrobot.sh --configure-exedev-email-bridge --stavrobot-dir /opt/stavrobot

  # 7) Optional: private Modal Qwen endpoint local proxy helper
  ./install-stavrobot.sh --configure-private-modal-qwen --stavrobot-dir /opt/stavrobot \
    --private-modal-upstream-url https://<workspace>--<app>.modal.run \
    --private-modal-token-id wk-... --private-modal-token-secret ws-... --private-modal-set-default

  # 8) Optional: status checks
  ./install-stavrobot.sh --print-shelley-mode-status --basic
  ./install-stavrobot.sh --print-shelley-mode-status
  ./install-stavrobot.sh --print-shelley-mode-status --json

Use --help for full expert/advanced flags.
EOF
}

usage() {
  cat <<'EOF'
Usage: ./install-stavrobot.sh --stavrobot-dir PATH [flags]

Flags:
  --stavrobot-dir PATH
  --refresh                     Pull/rebuild/restart when repo or config changed
  --plugins-only                Reuse saved plugin selections against a running stack
  --config-only                 Write .env/config only; skip pull, rebuild, and plugins
  --skip-config                 Reuse existing .env/config instead of prompting
  --skip-plugins                Skip plugin prompt/install steps
  --show-secrets
  --print-shelley-mode-status
  --json
  --basic
  --refresh-shelley-mode
  --allow-dirty-shelley
  --skip-shelley-smoke
  --expect-shelley-display-data Assert persisted display_data during Shelley smoke validation
  --require-shelley-display-hints  With --expect-shelley-display-data, fail if sampled turns have no display hints
  --expect-shelley-media-refs   Assert persisted media_refs when sampled turns contain image/media hints
  --require-shelley-media-refs  With --expect-shelley-media-refs, fail if no media-ref hints are observed
  --expect-shelley-native-raw-media-gating  Assert phase-2 runtime native raw-media mapping gate in smoke
  --require-shelley-native-raw-media-hints  With --expect-shelley-native-raw-media-gating, fail if no raw-inline hints are observed
  --expect-shelley-raw-media-rejection  Assert runtime rejection behavior for invalid raw-inline artifacts in smoke
  --require-shelley-raw-media-rejection-hints  With --expect-shelley-raw-media-rejection, fail if no invalid raw-inline hints are observed
  --expect-shelley-s2-markdown-tool-summary  Assert markdown-first content + display.tool_summary persistence behavior
  --require-shelley-s2-markdown-tool-summary-hints  With --expect-shelley-s2-markdown-tool-summary, fail if no markdown/tool_summary hints are observed
  --expect-shelley-s2-markdown-media-refs  Assert markdown-first content + media-ref persistence behavior
  --require-shelley-s2-markdown-media-refs-hints  With --expect-shelley-s2-markdown-media-refs, fail if no markdown/media-ref hints are observed
  --expect-shelley-s2-tool-summary-raw-fallback  Assert runtime derives display.tool_summary from raw.events when display.tool_summary is absent
  --require-shelley-s2-tool-summary-raw-fallback-hints  With --expect-shelley-s2-tool-summary-raw-fallback, fail if no raw.events hints are observed
  --shelley-bridge-fixture NAME  Optional test fixture mode for Shelley smoke bridge payloads
  --strict-shelley-raw-media-profile  Run authoritative strict managed raw-media proof profile during Shelley refresh
  --s2-shelley-narrow-fidelity-profile  Run deterministic S2 narrow-fidelity fixture proof profile during Shelley refresh
  --memory-suitability-gate-shelley-profile  Run aggregate required-runtime memory suitability gate profile during Shelley refresh
  --sync-shelley-upstream-ff-only   Fetch + pull --ff-only managed Shelley checkout before refresh patch/rebuild
  --refresh-shelley-mode-basic      Convenience alias: --refresh-shelley-mode + --sync-shelley-upstream-ff-only + --strict-shelley-raw-media-profile
  --refresh-shelley-mode-release    Convenience alias: --refresh-shelley-mode + --sync-shelley-upstream-ff-only + --memory-suitability-gate-shelley-profile
  --configure-cloudflare-email-worker   Run Cloudflare email worker helper using current Stavrobot config
  --deploy-cloudflare-email-worker      With --configure-cloudflare-email-worker, also run wrangler deploy + secret upload
  --cloudflare-worker-name NAME         Optional worker name override for Cloudflare helper
  --cloudflare-account-id ID            Optional Cloudflare account ID for generated wrangler.toml
  --configure-exedev-email-bridge       Run exe.dev Maildir->Stavrobot /email/webhook bridge helper
  --disable-exedev-email-bridge         With --configure-exedev-email-bridge, stop/disable bridge service
  --email-mode MODE                      Non-interactive email mode: smtp | exedev-relay | inbound-only
  --email-webhook-secret VALUE           Non-interactive email webhook secret
  --email-owner ADDRESS                  Non-interactive owner email override (required for exedev-relay)
  --email-smtp-host VALUE                Non-interactive SMTP host override (smtp mode)
  --email-smtp-port VALUE                Non-interactive SMTP port override (smtp mode)
  --email-smtp-user VALUE                Non-interactive SMTP user override (smtp mode)
  --email-smtp-password VALUE            Non-interactive SMTP password override (smtp mode)
  --email-from VALUE                     Non-interactive From address override (smtp mode)
  --configure-private-modal-qwen         Configure local private Modal OpenAI proxy service override
  --disable-private-modal-qwen           With --configure-private-modal-qwen, remove/disable private Modal proxy override
  --private-modal-upstream-url URL       Private Modal upstream base URL (e.g. https://<workspace>--<app>.modal.run)
  --private-modal-token-id ID            Modal Proxy Auth key id used by local proxy (wk-...)
  --private-modal-token-secret SECRET    Modal Proxy Auth secret used by local proxy (ws-...)
  --private-modal-proxy-token-id ID      Alias for --private-modal-token-id
  --private-modal-proxy-token-secret SECRET  Alias for --private-modal-token-secret
  --private-modal-model MODEL            Model id written into Stavrobot config profile (default: same as --private-modal-hf-model-id)
  --private-modal-hf-model-id MODEL      Hugging Face model repo id used by Modal app (default: Qwen/Qwen3.5-9B)
  --private-modal-context-window TOKENS  Context window for private modal profile (default: 16384)
  --private-modal-max-tokens TOKENS      Max output tokens for private modal profile (default: 8192)
  --private-modal-hf-token-file PATH     File containing Hugging Face token for gated/private model download
  --private-modal-set-default            Also set Stavrobot provider/model to private-modal profile
  --deploy-private-modal-qwen            Use Modal CLI to deploy production Qwen3.5-9B endpoint and auto-detect URL
  --private-modal-app-name NAME          Modal app name for deploy (default: private-modal-qwen35-9b)
  --private-modal-skip-prefetch          Skip one-time prefetch_model run before deploy
  --doctor                      Read-only environment/preflight checker for local installer + Shelley tooling
  --doctor --json               Emit machine-readable doctor output
  --help-basic                 Print basic user quickstart and common commands
  --help

Environment:
  STAVROBOT_BASE_URL   Local Stavrobot URL for readiness/plugin calls (default: http://localhost:8000)
  STAVROBOT_REPO_URL   Upstream Stavrobot repo URL to clone when --stavrobot-dir is missing (default: https://github.com/skorokithakis/stavrobot.git)
  MANAGED_SHELLEY_DIR  Managed Shelley checkout path for refresh/status lanes (default: /opt/shelley)

Shelley mode helpers:
  --print-shelley-mode-status   Read-only managed Shelley mode status
  --json                        With --print-shelley-mode-status, emit machine-readable JSON
  --basic                       With --print-shelley-mode-status, emit compact basic summary
  --refresh-shelley-mode        Apply/rebuild/smoke managed Shelley mode (default checkout: MANAGED_SHELLEY_DIR or /opt/shelley)
  --allow-dirty-shelley         Allow managed Shelley refresh against a dirty checkout
  --skip-shelley-smoke          Skip isolated Shelley smoke validation during refresh
  --expect-shelley-display-data Assert persisted display_data during Shelley smoke validation
  --require-shelley-display-hints  With --expect-shelley-display-data, fail if sampled turns have no display hints
  --expect-shelley-media-refs   Assert persisted media_refs when sampled turns contain image/media hints
  --require-shelley-media-refs  With --expect-shelley-media-refs, fail if no media-ref hints are observed
  --expect-shelley-native-raw-media-gating  Assert phase-2 runtime native raw-media mapping gate in smoke
  --require-shelley-native-raw-media-hints  With --expect-shelley-native-raw-media-gating, fail if no raw-inline hints are observed
  --expect-shelley-raw-media-rejection  Assert runtime rejection behavior for invalid raw-inline artifacts in smoke
  --require-shelley-raw-media-rejection-hints  With --expect-shelley-raw-media-rejection, fail if no invalid raw-inline hints are observed
  --expect-shelley-s2-markdown-tool-summary  Assert markdown-first content + display.tool_summary persistence behavior
  --require-shelley-s2-markdown-tool-summary-hints  With --expect-shelley-s2-markdown-tool-summary, fail if no markdown/tool_summary hints are observed
  --expect-shelley-s2-markdown-media-refs  Assert markdown-first content + media-ref persistence behavior
  --require-shelley-s2-markdown-media-refs-hints  With --expect-shelley-s2-markdown-media-refs, fail if no markdown/media-ref hints are observed
  --expect-shelley-s2-tool-summary-raw-fallback  Assert runtime derives display.tool_summary from raw.events when display.tool_summary is absent
  --require-shelley-s2-tool-summary-raw-fallback-hints  With --expect-shelley-s2-tool-summary-raw-fallback, fail if no raw.events hints are observed
  --shelley-bridge-fixture NAME  Optional test fixture mode for Shelley smoke bridge payloads
  --strict-shelley-raw-media-profile  Run authoritative strict managed raw-media proof profile during Shelley refresh
  --s2-shelley-narrow-fidelity-profile  Run deterministic S2 narrow-fidelity fixture proof profile during Shelley refresh
  --memory-suitability-gate-shelley-profile  Run aggregate required-runtime memory suitability gate profile during Shelley refresh
  --sync-shelley-upstream-ff-only   Fetch + pull --ff-only managed Shelley checkout before refresh patch/rebuild
  --refresh-shelley-mode-basic      Convenience alias: --refresh-shelley-mode + --sync-shelley-upstream-ff-only + --strict-shelley-raw-media-profile
  --refresh-shelley-mode-release    Convenience alias: --refresh-shelley-mode + --sync-shelley-upstream-ff-only + --memory-suitability-gate-shelley-profile
  --configure-cloudflare-email-worker   Run Cloudflare email worker helper using current Stavrobot config
  --deploy-cloudflare-email-worker      With --configure-cloudflare-email-worker, also run wrangler deploy + secret upload
  --cloudflare-worker-name NAME         Optional worker name override for Cloudflare helper
  --cloudflare-account-id ID            Optional Cloudflare account ID for generated wrangler.toml
  --configure-exedev-email-bridge       Run exe.dev Maildir->Stavrobot /email/webhook bridge helper
  --disable-exedev-email-bridge         With --configure-exedev-email-bridge, stop/disable bridge service
  --email-mode MODE                      Non-interactive email mode: smtp | exedev-relay | inbound-only
  --email-webhook-secret VALUE           Non-interactive email webhook secret
  --email-owner ADDRESS                  Non-interactive owner email override (required for exedev-relay)
  --email-smtp-host VALUE                Non-interactive SMTP host override (smtp mode)
  --email-smtp-port VALUE                Non-interactive SMTP port override (smtp mode)
  --email-smtp-user VALUE                Non-interactive SMTP user override (smtp mode)
  --email-smtp-password VALUE            Non-interactive SMTP password override (smtp mode)
  --email-from VALUE                     Non-interactive From address override (smtp mode)
  --configure-private-modal-qwen         Configure local private Modal OpenAI proxy service override
  --disable-private-modal-qwen           With --configure-private-modal-qwen, remove/disable private Modal proxy override
  --private-modal-upstream-url URL       Private Modal upstream base URL (e.g. https://<workspace>--<app>.modal.run)
  --private-modal-token-id ID            Modal Proxy Auth key id used by local proxy (wk-...)
  --private-modal-token-secret SECRET    Modal Proxy Auth secret used by local proxy (ws-...)
  --private-modal-proxy-token-id ID      Alias for --private-modal-token-id
  --private-modal-proxy-token-secret SECRET  Alias for --private-modal-token-secret
  --private-modal-model MODEL            Model id written into Stavrobot config profile (default: same as --private-modal-hf-model-id)
  --private-modal-hf-model-id MODEL      Hugging Face model repo id used by Modal app (default: Qwen/Qwen3.5-9B)
  --private-modal-context-window TOKENS  Context window for private modal profile (default: 16384)
  --private-modal-max-tokens TOKENS      Max output tokens for private modal profile (default: 8192)
  --private-modal-hf-token-file PATH     File containing Hugging Face token for gated/private model download
  --private-modal-set-default            Also set Stavrobot provider/model to private-modal profile
  --deploy-private-modal-qwen            Use Modal CLI to deploy production Qwen3.5-9B endpoint and auto-detect URL
  --private-modal-app-name NAME          Modal app name for deploy (default: private-modal-qwen35-9b)
  --private-modal-skip-prefetch          Skip one-time prefetch_model run before deploy
  --doctor                      Read-only environment/preflight checker for local installer + Shelley tooling
  --doctor --json               Emit machine-readable doctor output
EOF
}

json_quote() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

python_venv_usable() {
  local tmp
  tmp=$(mktemp -d)
  if python3 -m venv "$tmp/venv" >/dev/null 2>&1; then
    rm -rf "$tmp"
    return 0
  fi
  rm -rf "$tmp"
  return 1
}

ensure_python_venv_capable() {
  if python_venv_usable; then
    return 0
  fi
  die "python3 venv support is required (install package: python3-venv)"
}

run_doctor() {
  local as_json="${1:-0}"
  local -a required_cmds=(git python3 docker curl node npx go tmux)
  local ok_count=0
  local fail_count=0

  if [[ "$as_json" == "1" ]]; then
    python3 - "$ROOT_DIR" "$MANAGED_SHELLEY_DIR" <<'PY'
import json, os, shlex, shutil, subprocess, sys
root = sys.argv[1]
managed_shelley = sys.argv[2]
required_cmds = ["git", "python3", "docker", "curl", "node", "npx", "go", "tmux"]
required_files = [
  "install-stavrobot.sh",
  "refresh-shelley-managed-s1.sh",
  "print-shelley-managed-status.sh",
  "run-shelley-managed-memory-suitability-gate.sh",
  "validate-shelley-patch-series.sh",
]
patch_files = [f"patches/shelley/series/{i:04d}" for i in range(1, 10)]
state_path = "/var/lib/stavrobot-installer/shelley-bridge-profiles.json"

def run(cmd):
    try:
      p = subprocess.run(cmd, shell=True, text=True, capture_output=True)
      return p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip()
    except Exception as e:
      return 1, "", str(e)

checks = []
for c in required_cmds:
    checks.append({"name": f"cmd:{c}", "ok": shutil.which(c) is not None})
rc, _, _ = run("python3 -m venv /tmp/.installer-doctor-venv-$$")
run("rm -rf /tmp/.installer-doctor-venv-$$")
checks.append({"name": "python:venv", "ok": rc == 0, "hint": "install python3-venv" if rc != 0 else ""})
for f in required_files:
    checks.append({"name": f"file:{f}", "ok": os.path.isfile(os.path.join(root, f))})
for p in patch_files:
    matches = [x for x in os.listdir(os.path.join(root, "patches/shelley/series")) if x.startswith(os.path.basename(p)+"-") and x.endswith(".patch")]
    checks.append({"name": f"patch:{os.path.basename(p)}", "ok": len(matches) == 1})
checks.append({"name": "state:bridge-profiles", "ok": os.path.isfile(state_path)})
checks.append({"name": f"dir:{managed_shelley}", "ok": os.path.isdir(managed_shelley)})
if os.path.isdir(os.path.join(managed_shelley, ".git")):
    rc, out, _ = run(f"git -C {shlex.quote(managed_shelley)} rev-parse --short HEAD")
    checks.append({"name": "managed-shelley:git", "ok": rc == 0, "value": out if rc == 0 else "", "path": managed_shelley})
else:
    checks.append({"name": "managed-shelley:git", "ok": False, "path": managed_shelley})

ok = sum(1 for c in checks if c.get("ok"))
fail = sum(1 for c in checks if not c.get("ok"))
print(json.dumps({"ok": fail == 0, "ok_count": ok, "fail_count": fail, "checks": checks}, indent=2))
PY
    return 0
  fi

  info "Running installer doctor preflight"
  for cmd in "${required_cmds[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '[ok] cmd:%s\n' "$cmd"
      ((ok_count+=1))
    else
      printf '[fail] cmd:%s (missing)\n' "$cmd"
      ((fail_count+=1))
    fi
  done

  if python_venv_usable; then
    printf '[ok] python:venv\n'
    ((ok_count+=1))
  else
    printf '[fail] python:venv (missing support; install python3-venv)\n'
    ((fail_count+=1))
  fi

  for path in \
    "$ROOT_DIR/install-stavrobot.sh" \
    "$ROOT_DIR/refresh-shelley-managed-s1.sh" \
    "$ROOT_DIR/print-shelley-managed-status.sh" \
    "$ROOT_DIR/run-shelley-managed-memory-suitability-gate.sh" \
    "$ROOT_DIR/validate-shelley-patch-series.sh"; do
    if [[ -f "$path" ]]; then
      printf '[ok] file:%s\n' "${path#$ROOT_DIR/}"
      ((ok_count+=1))
    else
      printf '[fail] file:%s (missing)\n' "${path#$ROOT_DIR/}"
      ((fail_count+=1))
    fi
  done

  local patch_dir="$ROOT_DIR/patches/shelley/series"
  for n in 0001 0002 0003 0004 0005 0006 0007 0008 0009; do
    if compgen -G "$patch_dir/${n}-*.patch" >/dev/null; then
      printf '[ok] patch:%s\n' "$n"
      ((ok_count+=1))
    else
      printf '[fail] patch:%s (missing)\n' "$n"
      ((fail_count+=1))
    fi
  done

  if [[ -f /var/lib/stavrobot-installer/shelley-bridge-profiles.json ]]; then
    printf '[ok] state:bridge-profiles\n'
    ((ok_count+=1))
  else
    printf '[warn] state:bridge-profiles missing (managed Shelley refresh may fail until installer state exists)\n'
  fi

  if [[ -d "$MANAGED_SHELLEY_DIR/.git" ]]; then
    local shelley_head
    shelley_head=$(git -C "$MANAGED_SHELLEY_DIR" rev-parse --short HEAD 2>/dev/null || true)
    printf '[ok] managed-shelley:git (%s @ %s)\n' "${shelley_head:-unknown}" "$MANAGED_SHELLEY_DIR"
    ((ok_count+=1))
  else
    printf '[warn] managed-shelley:git missing at %s (Shelley refresh/status paths unavailable until checkout exists)\n' "$MANAGED_SHELLEY_DIR"
  fi

  printf '[summary] ok=%d fail=%d\n' "$ok_count" "$fail_count"
  if (( fail_count > 0 )); then
    die "Doctor preflight failed"
  fi
  info "Doctor preflight passed"
}

append_plugin_report() {
  local line="$1"
  printf '%s\n' "$line" >> "$PLUGIN_REPORT_FILE"
}

render_current_state() {
  CURRENT_JSON="$ROOT_DIR/state/current-config.json"
  python3 "$ROOT_DIR/py/load_current_config.py" \
    "$STAVROBOT_DIR/env.example" \
    "$ENV_PATH" \
    "$STAVROBOT_DIR/config.example.toml" \
    "$CONFIG_PATH" > "$CURRENT_JSON"
  ensure_private_file "$CURRENT_JSON"
}

fetch_openrouter_suggestions() {
  OPENROUTER_OUT="$ROOT_DIR/state/openrouter-free-models.json"
  if python3 "$ROOT_DIR/py/openrouter_models.py" > "$OPENROUTER_OUT"; then
    ensure_private_file "$OPENROUTER_OUT"
    info "Fetched OpenRouter free model suggestions into $OPENROUTER_OUT"
    return 0
  fi
  warn "Failed to fetch OpenRouter free model suggestions"
  return 1
}

prompt_openrouter_model() {
  local current_model="$1"
  local default_model="${current_model:-openrouter/free}"
  local openrouter_catalog="${OPENROUTER_OUT:-$ROOT_DIR/state/openrouter-free-models.json}"
  local -a model_choices=()

  if [[ -f "$openrouter_catalog" ]]; then
    mapfile -t model_choices < <(python3 - "$openrouter_catalog" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    raise SystemExit(0)
for item in data.get('models', [])[:12]:
    model_id = item.get('id', '').strip()
    if model_id:
        print(model_id)
PY
)
  fi

  if (( ${#model_choices[@]} > 0 )); then
    printf '[info] OpenRouter free-model choices are from the current live catalog\n' >&2
    selection=$(prompt_choice "OpenRouter model:" "${model_choices[@]}" "Manual entry")
    if [[ "$selection" == "Manual entry" ]]; then
      selection=$(prompt_text "OpenRouter model ID" "$default_model")
    fi
  else
    selection=$(prompt_text "OpenRouter model ID" "$default_model")
  fi

  selection=${selection:-$default_model}
  [[ -n "$selection" ]] || die "OpenRouter model ID is required"
  printf '%s\n' "$selection"
}

load_runtime_password() {
  if [[ -f "$ROOT_DIR/state/render-config.json" ]]; then
    PASSWORD_FOR_READY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("password", ""))' "$ROOT_DIR/state/render-config.json" 2>/dev/null || true)
  elif [[ -f "$CONFIG_PATH" ]]; then
    PASSWORD_FOR_READY=$(python3 - "$CONFIG_PATH" <<'PY'
import sys, tomllib
try:
    data = tomllib.loads(open(sys.argv[1]).read())
    print(data.get('password', ''))
except Exception:
    print('')
PY
)
  fi
}

load_runtime_metadata() {
  if [[ -f "$CONFIG_PATH" ]]; then
    eval "$(python3 - "$CONFIG_PATH" <<'PY'
import sys, tomllib
try:
    data = tomllib.loads(open(sys.argv[1]).read())
except Exception:
    data = {}
password = data.get('password', '')
public_hostname = data.get('publicHostname', '[unchanged]')
auth_mode = 'apiKey' if data.get('apiKey') else ('authFile' if data.get('authFile') else 'unknown')
coder_enabled = 'true' if data.get('coder') else 'false'
signal_enabled = 'true' if data.get('signal') else 'false'
whatsapp_enabled = 'true' if data.get('whatsapp') else 'false'
email = data.get('email') or {}
email_enabled = 'true' if email else 'false'
email_transport_mode = 'smtp'
if (email.get('smtpHost') == 'host.docker.internal' and int(email.get('smtpPort', 0) or 0) == 2525 and
    email.get('smtpUser') == 'relay' and email.get('smtpPassword') == 'relay'):
    email_transport_mode = 'exedev-relay'
elif email and not email.get('smtpHost'):
    email_transport_mode = 'inbound-only'
owner_email = (data.get('owner') or {}).get('email', '')
print(f'PASSWORD_FOR_READY={password!r}')
print(f'PUBLIC_HOSTNAME_FINAL={public_hostname!r}')
print(f'AUTH_MODE_FINAL={auth_mode!r}')
print(f'CODER_ENABLED={coder_enabled!r}')
print(f'SIGNAL_ENABLED={signal_enabled!r}')
print(f'WHATSAPP_ENABLED={whatsapp_enabled!r}')
print(f'EMAIL_ENABLED={email_enabled!r}')
print(f'EMAIL_TRANSPORT_MODE={email_transport_mode!r}')
print(f'OWNER_EMAIL={owner_email!r}')
PY
)"
  fi
}

write_private_modal_profile_state() {
  local upstream_url="$1"
  local token_id="$2"
  local token_secret="$3"
  local model="$4"
  local context_window="$5"
  local max_tokens="$6"
  local state_path="$ROOT_DIR/state/llm-profiles.json"

  python3 - "$state_path" "$upstream_url" "$token_id" "$token_secret" "$model" "$context_window" "$max_tokens" <<'PY'
import json, os, sys
path, upstream_url, token_id, token_secret, model, context_window, max_tokens = sys.argv[1:]
profiles = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            payload = json.load(f)
        if isinstance(payload, dict):
            profiles = payload
    except Exception:
        profiles = {}
profiles.setdefault("profiles", {})
profiles["profiles"]["private-modal-qwen"] = {
    "name": "Private Modal endpoint (Qwen3.5-9B)",
    "provider": "openai",
    "model": model,
    "api": "openai-completions",
    "baseUrl": "http://private-modal-llm-proxy:11435/v1",
    "apiKey": "private-modal-local-proxy",
    "contextWindow": int(context_window),
    "maxTokens": int(max_tokens),
    "modal": {
        "upstream_url": upstream_url,
        "token_id": token_id,
        "token_secret": token_secret,
    },
}
with open(path, "w") as f:
    json.dump(profiles, f, indent=2)
PY
  ensure_private_file "$state_path"
}

apply_private_modal_profile_to_config() {
  local model="$1"
  local context_window="$2"
  local max_tokens="$3"

  python3 - "$CONFIG_PATH" "$model" "$context_window" "$max_tokens" <<'PY'
import re, sys
path, model, context_window, max_tokens = sys.argv[1:]
text = open(path).read()

section_match = re.search(r'(?m)^\[', text)
if section_match:
    top = text[:section_match.start()]
    rest = text[section_match.start():]
else:
    top = text
    rest = ""

def set_or_add_top(top, pattern, line):
    rx = re.compile(pattern, re.MULTILINE)
    if rx.search(top):
        return rx.sub(line, top, count=1)
    top = top.rstrip() + "\n" if top.strip() else ""
    return top + line + "\n"

def remove_top(top, pattern):
    return re.sub(pattern, '', top, flags=re.MULTILINE)

top = set_or_add_top(top, r'^provider\s*=\s*"[^"]*"\s*$', 'provider = "openai"')
top = set_or_add_top(top, r'^model\s*=\s*"[^"]*"\s*$', f'model = "{model}"')
top = set_or_add_top(top, r'^apiKey\s*=\s*"[^"]*"\s*$', 'apiKey = "private-modal-local-proxy"')
top = set_or_add_top(top, r'^baseUrl\s*=\s*"[^"]*"\s*$', 'baseUrl = "http://private-modal-llm-proxy:11435/v1"')
top = set_or_add_top(top, r'^api\s*=\s*"[^"]*"\s*$', 'api = "openai-completions"')
top = set_or_add_top(top, r'^contextWindow\s*=\s*[0-9]+\s*$', f'contextWindow = {int(context_window)}')
top = set_or_add_top(top, r'^maxTokens\s*=\s*[0-9]+\s*$', f'maxTokens = {int(max_tokens)}')
top = remove_top(top, r'^authFile\s*=\s*"[^"]*"\s*$\n?')

new_text = top.rstrip() + "\n\n" + rest.lstrip("\n") if rest else top.rstrip() + "\n"

owner_match = re.search(r'(?ms)^\[owner\]\n(.*?)(^\[[^\]]+\]\n|\Z)', new_text)
if owner_match:
    owner_body = owner_match.group(1)
    owner_body = re.sub(r'(?m)^(baseUrl|api|contextWindow|maxTokens)\s*=\s*.*\n?', '', owner_body)
    owner_rebuilt = '[owner]\n' + owner_body.rstrip() + '\n'
    tail = owner_match.group(2)
    new_text = new_text[:owner_match.start()] + owner_rebuilt + tail + new_text[owner_match.end():]

open(path, 'w').write(new_text)
PY
}

strip_seeded_telegram_config_if_disabled() {
  local config_path="$1"

  python3 - "$config_path" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()

owner_match = re.search(r'(?ms)^\[owner\]\n(.*?)(^\[[^\]]+\]\n|\Z)', text)
if owner_match:
    owner_body = owner_match.group(1)
    owner_body = re.sub(r'(?m)^telegram\s*=\s*"[^"]*"\s*\n?', '', owner_body)
    owner_rebuilt = '[owner]\n' + owner_body.rstrip() + '\n'
    tail = owner_match.group(2)
    text = text[:owner_match.start()] + owner_rebuilt + tail + text[owner_match.end():]

owner_match = re.search(r'(?ms)^\[owner\]\n(.*?)(?=^\[[^\]]+\]\n|\Z)', text)
owner_body = owner_match.group(1) if owner_match else ""
owner_telegram_match = re.search(r'(?m)^telegram\s*=\s*"([^"]*)"\s*$', owner_body)
owner_telegram = (owner_telegram_match.group(1).strip() if owner_telegram_match else "")

telegram_section = re.search(r'(?ms)^\[telegram\]\n.*?(?=^\[[^\]]+\]\n|\Z)', text)
if telegram_section:
    body = telegram_section.group(0)
    bot_match = re.search(r'(?m)^botToken\s*=\s*"([^"]*)"\s*$', body)
    bot_token = (bot_match.group(1).strip() if bot_match else "")
    is_seed_placeholder = bot_token in {
        "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11",
        "<TELEGRAM_BOT_TOKEN>",
    } or bot_token.startswith("123456:ABC-DEF")
    should_remove_telegram = (not bot_token) or (is_seed_placeholder and not owner_telegram)
    if should_remove_telegram:
        text = text[:telegram_section.start()] + text[telegram_section.end():]

open(path, 'w').write(text.rstrip() + '\n')
PY
}

wait_for_stavrobot_ready() {
  local local_base_url="$STAVROBOT_BASE_URL"
  [[ -n "$PASSWORD_FOR_READY" ]] || die "Could not determine Stavrobot password for readiness checks"
  if wait_for_http_basic_auth "$local_base_url/" "$PASSWORD_FOR_READY" 120; then
    info "Stavrobot is responding at $local_base_url"
    if stavrobot_list_plugins "$local_base_url" "$PASSWORD_FOR_READY" >/dev/null 2>&1; then
      info "Plugin settings endpoint is reachable"
    else
      warn "Plugin settings endpoint check failed"
    fi
  else
    die "Stavrobot did not become ready within timeout"
  fi
}

run_plugins_from_state() {
  local local_base_url="$STAVROBOT_BASE_URL"
  [[ -f "$PLUGIN_STATE_JSON" ]] || return 0
  [[ -n "$PASSWORD_FOR_READY" ]] || die "Missing password for plugin installation"
  while IFS= read -r plugin_entry; do
    [[ -n "$plugin_entry" ]] || continue
    plugin_name=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["name"])' "$plugin_entry")
    plugin_repo=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["repo_url"])' "$plugin_entry")
    plugin_config=$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["config"]))' "$plugin_entry")
    info "Installing plugin $plugin_name"
    install_response=$(stavrobot_install_plugin "$local_base_url" "$PASSWORD_FOR_READY" "$plugin_repo" || true)
    install_status=$(printf '%s' "$install_response" | python3 -c 'import json,sys; data=json.load(sys.stdin); print("already installed" if "already installed" in str(data.get("error","")) else ("ok" if "error" not in data else "error"))')
    if [[ "$install_status" == "error" ]]; then
      printf '%s\n' "$install_response" >&2
      append_plugin_report "$plugin_name: install failed"
      die "Failed to install plugin $plugin_name"
    fi
    if [[ "$install_status" == "already installed" ]]; then
      append_plugin_report "$plugin_name: already installed"
    else
      append_plugin_report "$plugin_name: installed"
    fi
    if [[ "$plugin_config" != "{}" ]]; then
      info "Configuring plugin $plugin_name"
      configure_response=$(stavrobot_configure_plugin "$local_base_url" "$PASSWORD_FOR_READY" "$plugin_name" "$plugin_config" || true)
      if ! printf '%s' "$configure_response" | python3 -c 'import json,sys; data=json.load(sys.stdin); import sys as s; s.exit(0 if "error" not in data else 1)'; then
        printf '%s\n' "$configure_response" >&2
        append_plugin_report "$plugin_name: configure failed"
        die "Failed to configure plugin $plugin_name"
      fi
      warnings=$(printf '%s' "$configure_response" | python3 -c 'import json,sys; data=json.load(sys.stdin); print("; ".join(data.get("warnings", [])))')
      if [[ -n "$warnings" ]]; then
        append_plugin_report "$plugin_name: configured with warnings: $warnings"
      else
        append_plugin_report "$plugin_name: configured"
      fi
    fi
    ((PLUGINS_HANDLED+=1))
  done < <(python3 -c 'import json,sys; [print(json.dumps(x)) for x in json.load(open(sys.argv[1])).get("plugins", [])]' "$PLUGIN_STATE_JSON")
}

prompt_plugin_selection() {
  local plugin_tmp="$ROOT_DIR/state/plugin-selections.jsonl"
  : > "$plugin_tmp"
  while IFS= read -r plugin_json; do
    name=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["name"])' "$plugin_json")
    description=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["description"])' "$plugin_json")
    repo_url=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["repo_url"])' "$plugin_json")
    default_yes=$(python3 -c 'import json,sys; print("Y" if json.loads(sys.argv[1]).get("enabled_by_default") else "N")' "$plugin_json")
    if prompt_yes_no "Install plugin '$name' ($description)?" "$default_yes"; then
      ((PLUGINS_SELECTED_COUNT+=1))
      config_json='{}'
      while IFS= read -r field_json; do
        [[ -n "$field_json" ]] || continue
        field_key=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["key"])' "$field_json")
        field_prompt=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["prompt"])' "$field_json")
        field_secret=$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("secret") else "0")' "$field_json")
        field_default=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("default", ""))' "$field_json")
        if [[ "$field_secret" == "1" ]]; then
          field_value=$(prompt_secret "$field_prompt" "$field_default")
        else
          field_value=$(prompt_text "$field_prompt" "$field_default")
        fi
        field_value=${field_value:-$field_default}
        [[ -n "$field_value" ]] || die "Plugin '$name' requires '$field_key'"
        config_json=$(python3 - "$config_json" "$field_key" "$field_value" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
obj[sys.argv[2]] = sys.argv[3]
print(json.dumps(obj))
PY
)
      done < <(python3 -c 'import json,sys; plugin=json.loads(sys.argv[1]); [print(json.dumps(x)) for x in plugin.get("required_config", [])]' "$plugin_json")

      while IFS= read -r field_json; do
        [[ -n "$field_json" ]] || continue
        field_key=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["key"])' "$field_json")
        field_prompt=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["prompt"])' "$field_json")
        field_secret=$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("secret") else "0")' "$field_json")
        field_default=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("default", ""))' "$field_json")
        if [[ "$field_secret" == "1" ]]; then
          field_value=$(prompt_secret "$field_prompt (optional; press Enter to keep default)" "$field_default")
        else
          field_value=$(prompt_optional_text "$field_prompt (optional; type SKIP to omit)" "$field_default")
        fi
        if [[ "$field_value" == "__SKIP__" ]]; then
          continue
        fi
        field_value=${field_value:-$field_default}
        if [[ -n "$field_value" ]]; then
          config_json=$(python3 - "$config_json" "$field_key" "$field_value" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
obj[sys.argv[2]] = sys.argv[3]
print(json.dumps(obj))
PY
)
        fi
      done < <(python3 -c 'import json,sys; plugin=json.loads(sys.argv[1]); [print(json.dumps(x)) for x in plugin.get("optional_config", [])]' "$plugin_json")

      python3 - "$name" "$repo_url" "$config_json" >> "$plugin_tmp" <<'PY'
import json, sys
print(json.dumps({"name": sys.argv[1], "repo_url": sys.argv[2], "config": json.loads(sys.argv[3])}))
PY
    fi
  done < <(python3 -c 'import json,sys; [print(json.dumps(x)) for x in json.load(open(sys.argv[1]))]' "$ROOT_DIR/data/plugin-catalog.json")

  python3 - "$plugin_tmp" > "$PLUGIN_STATE_JSON" <<'PY'
import json, sys
entries = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line:
            entries.append(json.loads(line))
print(json.dumps({"plugins": entries}, indent=2))
PY
  ensure_private_file "$PLUGIN_STATE_JSON"
  rm -f "$plugin_tmp"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stavrobot-dir)
      STAVROBOT_DIR="$2"
      shift 2
      ;;
    --refresh)
      REFRESH_ONLY=1
      shift
      ;;
    --plugins-only)
      PLUGINS_ONLY=1
      shift
      ;;
    --config-only)
      CONFIG_ONLY=1
      shift
      ;;
    --skip-config)
      SKIP_CONFIG=1
      shift
      ;;
    --skip-plugins)
      SKIP_PLUGINS=1
      shift
      ;;
    --show-secrets)
      SHOW_SECRETS=1
      shift
      ;;
    --print-shelley-mode-status)
      SHELLEY_STATUS_ONLY=1
      shift
      ;;
    --json)
      SHELLEY_STATUS_JSON=1
      shift
      ;;
    --basic)
      SHELLEY_STATUS_BASIC=1
      shift
      ;;
    --refresh-shelley-mode)
      SHELLEY_REFRESH_ONLY=1
      shift
      ;;
    --allow-dirty-shelley)
      SHELLEY_ALLOW_DIRTY=1
      shift
      ;;
    --skip-shelley-smoke)
      SHELLEY_SKIP_SMOKE=1
      shift
      ;;
    --expect-shelley-display-data)
      SHELLEY_EXPECT_DISPLAY_DATA=1
      shift
      ;;
    --require-shelley-display-hints)
      SHELLEY_REQUIRE_DISPLAY_HINTS=1
      shift
      ;;
    --expect-shelley-media-refs)
      SHELLEY_EXPECT_MEDIA_REFS=1
      shift
      ;;
    --require-shelley-media-refs)
      SHELLEY_REQUIRE_MEDIA_REFS=1
      shift
      ;;
    --expect-shelley-native-raw-media-gating)
      SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING=1
      shift
      ;;
    --require-shelley-native-raw-media-hints)
      SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS=1
      shift
      ;;
    --expect-shelley-raw-media-rejection)
      SHELLEY_EXPECT_RAW_MEDIA_REJECTION=1
      shift
      ;;
    --require-shelley-raw-media-rejection-hints)
      SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS=1
      shift
      ;;
    --expect-shelley-s2-markdown-tool-summary)
      SHELLEY_EXPECT_S2_MARKDOWN_TOOL_SUMMARY=1
      shift
      ;;
    --require-shelley-s2-markdown-tool-summary-hints)
      SHELLEY_REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS=1
      shift
      ;;
    --expect-shelley-s2-markdown-media-refs)
      SHELLEY_EXPECT_S2_MARKDOWN_MEDIA_REFS=1
      shift
      ;;
    --require-shelley-s2-markdown-media-refs-hints)
      SHELLEY_REQUIRE_S2_MARKDOWN_MEDIA_REFS_HINTS=1
      shift
      ;;
    --expect-shelley-s2-tool-summary-raw-fallback)
      SHELLEY_EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK=1
      shift
      ;;
    --require-shelley-s2-tool-summary-raw-fallback-hints)
      SHELLEY_REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS=1
      shift
      ;;
    --shelley-bridge-fixture)
      SHELLEY_BRIDGE_FIXTURE="$2"
      shift 2
      ;;
    --strict-shelley-raw-media-profile)
      SHELLEY_STRICT_RAW_MEDIA_PROFILE=1
      shift
      ;;
    --s2-shelley-narrow-fidelity-profile)
      SHELLEY_S2_NARROW_FIDELITY_PROFILE=1
      shift
      ;;
    --memory-suitability-gate-shelley-profile)
      SHELLEY_MEMORY_SUITABILITY_GATE_PROFILE=1
      shift
      ;;
    --sync-shelley-upstream-ff-only)
      SHELLEY_SYNC_UPSTREAM_FF_ONLY=1
      shift
      ;;
    --refresh-shelley-mode-basic)
      SHELLEY_REFRESH_BASIC=1
      shift
      ;;
    --refresh-shelley-mode-release)
      SHELLEY_REFRESH_RELEASE=1
      shift
      ;;
    --configure-cloudflare-email-worker)
      CF_EMAIL_WORKER_ONLY=1
      shift
      ;;
    --deploy-cloudflare-email-worker)
      CF_EMAIL_WORKER_DEPLOY=1
      shift
      ;;
    --cloudflare-worker-name)
      CF_EMAIL_WORKER_NAME="$2"
      shift 2
      ;;
    --cloudflare-account-id)
      CF_EMAIL_WORKER_ACCOUNT_ID="$2"
      shift 2
      ;;
    --configure-exedev-email-bridge)
      EXEDEV_EMAIL_BRIDGE_ONLY=1
      shift
      ;;
    --disable-exedev-email-bridge)
      EXEDEV_EMAIL_BRIDGE_DISABLE=1
      shift
      ;;
    --email-mode)
      EMAIL_MODE_OVERRIDE="$2"
      shift 2
      ;;
    --email-webhook-secret)
      EMAIL_WEBHOOK_SECRET_OVERRIDE="$2"
      shift 2
      ;;
    --email-owner)
      EMAIL_OWNER_OVERRIDE="$2"
      shift 2
      ;;
    --email-smtp-host)
      EMAIL_SMTP_HOST_OVERRIDE="$2"
      shift 2
      ;;
    --email-smtp-port)
      EMAIL_SMTP_PORT_OVERRIDE="$2"
      shift 2
      ;;
    --email-smtp-user)
      EMAIL_SMTP_USER_OVERRIDE="$2"
      shift 2
      ;;
    --email-smtp-password)
      EMAIL_SMTP_PASSWORD_OVERRIDE="$2"
      shift 2
      ;;
    --email-from)
      EMAIL_FROM_OVERRIDE="$2"
      shift 2
      ;;
    --configure-private-modal-qwen)
      PRIVATE_MODAL_ENABLE=1
      shift
      ;;
    --disable-private-modal-qwen)
      PRIVATE_MODAL_ENABLE=1
      PRIVATE_MODAL_DISABLE=1
      PRIVATE_MODAL_SET_DEFAULT=0
      shift
      ;;
    --private-modal-upstream-url)
      PRIVATE_MODAL_UPSTREAM_URL_OVERRIDE="$2"
      shift 2
      ;;
    --private-modal-token-id|--private-modal-proxy-token-id)
      PRIVATE_MODAL_TOKEN_ID_OVERRIDE="$2"
      PRIVATE_MODAL_PROXY_TOKEN_ID_OVERRIDE="$2"
      shift 2
      ;;
    --private-modal-token-secret|--private-modal-proxy-token-secret)
      PRIVATE_MODAL_TOKEN_SECRET_OVERRIDE="$2"
      PRIVATE_MODAL_PROXY_TOKEN_SECRET_OVERRIDE="$2"
      shift 2
      ;;
    --private-modal-model)
      PRIVATE_MODAL_MODEL_OVERRIDE="$2"
      shift 2
      ;;
    --private-modal-hf-model-id)
      PRIVATE_MODAL_HF_MODEL_ID_OVERRIDE="$2"
      shift 2
      ;;
    --private-modal-context-window)
      PRIVATE_MODAL_CONTEXT_WINDOW_OVERRIDE="$2"
      shift 2
      ;;
    --private-modal-max-tokens)
      PRIVATE_MODAL_MAX_TOKENS_OVERRIDE="$2"
      shift 2
      ;;
    --private-modal-hf-token-file)
      PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE="$2"
      shift 2
      ;;
    --private-modal-set-default)
      PRIVATE_MODAL_SET_DEFAULT=1
      shift
      ;;
    --deploy-private-modal-qwen)
      PRIVATE_MODAL_DEPLOY=1
      PRIVATE_MODAL_ENABLE=1
      shift
      ;;
    --private-modal-app-name)
      PRIVATE_MODAL_APP_NAME_OVERRIDE="$2"
      shift 2
      ;;
    --private-modal-skip-prefetch)
      PRIVATE_MODAL_SKIP_PREFETCH=1
      shift
      ;;
    --doctor)
      DOCTOR_ONLY=1
      shift
      ;;
    --help-basic)
      usage_basic
      exit 0
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

if (( SHELLEY_REFRESH_BASIC )); then
  SHELLEY_REFRESH_ONLY=1
  SHELLEY_SYNC_UPSTREAM_FF_ONLY=1
  SHELLEY_STRICT_RAW_MEDIA_PROFILE=1
fi

if (( SHELLEY_REFRESH_RELEASE )); then
  SHELLEY_REFRESH_ONLY=1
  SHELLEY_SYNC_UPSTREAM_FF_ONLY=1
  SHELLEY_MEMORY_SUITABILITY_GATE_PROFILE=1
fi

if (( DOCTOR_ONLY )) && (( SHELLEY_STATUS_JSON )); then
  DOCTOR_JSON=1
  SHELLEY_STATUS_JSON=0
fi

if (( SHELLEY_REFRESH_ONLY )) && (( SHELLEY_STATUS_JSON )); then
  die "--json cannot be combined with --refresh-shelley-mode"
fi
if (( CF_EMAIL_WORKER_ONLY == 0 && (CF_EMAIL_WORKER_DEPLOY == 1 || ${#CF_EMAIL_WORKER_NAME} > 0 || ${#CF_EMAIL_WORKER_ACCOUNT_ID} > 0) )); then
  die "--deploy-cloudflare-email-worker, --cloudflare-worker-name, and --cloudflare-account-id require --configure-cloudflare-email-worker"
fi
if (( EXEDEV_EMAIL_BRIDGE_DISABLE == 1 && EXEDEV_EMAIL_BRIDGE_ONLY == 0 )); then
  die "--disable-exedev-email-bridge requires --configure-exedev-email-bridge"
fi
if (( CF_EMAIL_WORKER_ONLY == 1 && SHELLEY_REFRESH_ONLY == 1 )); then
  die "--configure-cloudflare-email-worker cannot be combined with --refresh-shelley-mode"
fi
if (( EXEDEV_EMAIL_BRIDGE_ONLY == 1 && SHELLEY_REFRESH_ONLY == 1 )); then
  die "--configure-exedev-email-bridge cannot be combined with --refresh-shelley-mode"
fi
if (( PRIVATE_MODAL_ENABLE == 1 && SHELLEY_REFRESH_ONLY == 1 )); then
  die "--configure-private-modal-qwen cannot be combined with --refresh-shelley-mode"
fi
if (( CF_EMAIL_WORKER_ONLY == 1 && (SHELLEY_STATUS_JSON == 1 || SHELLEY_STATUS_BASIC == 1) )); then
  die "--json/--basic cannot be combined with --configure-cloudflare-email-worker"
fi
if (( EXEDEV_EMAIL_BRIDGE_ONLY == 1 && (SHELLEY_STATUS_JSON == 1 || SHELLEY_STATUS_BASIC == 1) )); then
  die "--json/--basic cannot be combined with --configure-exedev-email-bridge"
fi
if (( PRIVATE_MODAL_ENABLE == 1 && (SHELLEY_STATUS_JSON == 1 || SHELLEY_STATUS_BASIC == 1) )); then
  die "--json/--basic cannot be combined with --configure-private-modal-qwen"
fi
if (( CF_EMAIL_WORKER_ONLY == 1 && EXEDEV_EMAIL_BRIDGE_ONLY == 1 )); then
  die "--configure-cloudflare-email-worker cannot be combined with --configure-exedev-email-bridge"
fi
if (( CF_EMAIL_WORKER_ONLY == 1 && PRIVATE_MODAL_ENABLE == 1 )); then
  die "--configure-cloudflare-email-worker cannot be combined with --configure-private-modal-qwen"
fi
if (( EXEDEV_EMAIL_BRIDGE_ONLY == 1 && PRIVATE_MODAL_ENABLE == 1 )); then
  die "--configure-exedev-email-bridge cannot be combined with --configure-private-modal-qwen"
fi
if (( SHELLEY_REFRESH_ONLY )) && (( SHELLEY_STATUS_BASIC )); then
  die "--basic cannot be combined with --refresh-shelley-mode"
fi
if (( SHELLEY_STATUS_JSON )) && (( SHELLEY_STATUS_BASIC )); then
  die "--json cannot be combined with --basic"
fi
if (( DOCTOR_ONLY )) && (( SHELLEY_REFRESH_ONLY || SHELLEY_STATUS_ONLY || REFRESH_ONLY || PLUGINS_ONLY || CONFIG_ONLY || SKIP_CONFIG || SKIP_PLUGINS || SHOW_SECRETS || CF_EMAIL_WORKER_ONLY || CF_EMAIL_WORKER_DEPLOY || EXEDEV_EMAIL_BRIDGE_ONLY || EXEDEV_EMAIL_BRIDGE_DISABLE || PRIVATE_MODAL_ENABLE )) || [[ -n "$EMAIL_MODE_OVERRIDE$EMAIL_WEBHOOK_SECRET_OVERRIDE$EMAIL_OWNER_OVERRIDE$EMAIL_SMTP_HOST_OVERRIDE$EMAIL_SMTP_PORT_OVERRIDE$EMAIL_SMTP_USER_OVERRIDE$EMAIL_SMTP_PASSWORD_OVERRIDE$EMAIL_FROM_OVERRIDE" ]]; then
  if (( DOCTOR_ONLY )); then
    die "--doctor cannot be combined with installer mutation or Shelley refresh/status flags"
  fi
fi

if [[ -n "$EMAIL_MODE_OVERRIDE$EMAIL_WEBHOOK_SECRET_OVERRIDE$EMAIL_OWNER_OVERRIDE$EMAIL_SMTP_HOST_OVERRIDE$EMAIL_SMTP_PORT_OVERRIDE$EMAIL_SMTP_USER_OVERRIDE$EMAIL_SMTP_PASSWORD_OVERRIDE$EMAIL_FROM_OVERRIDE" ]]; then
  if (( SHELLEY_REFRESH_ONLY || SHELLEY_STATUS_ONLY || CF_EMAIL_WORKER_ONLY || EXEDEV_EMAIL_BRIDGE_ONLY || PRIVATE_MODAL_ENABLE )); then
    die "--email-* flags cannot be combined with Shelley status/refresh or helper-only modes"
  fi
  if [[ -z "$EMAIL_MODE_OVERRIDE" ]]; then
    die "--email-mode is required when using non-interactive --email-* overrides"
  fi
  case "$EMAIL_MODE_OVERRIDE" in
    smtp|exedev-relay|inbound-only) ;;
    *) die "--email-mode must be one of: smtp, exedev-relay, inbound-only" ;;
  esac
fi

if (( PRIVATE_MODAL_ENABLE == 0 )) && [[ -n "$PRIVATE_MODAL_UPSTREAM_URL_OVERRIDE$PRIVATE_MODAL_TOKEN_ID_OVERRIDE$PRIVATE_MODAL_TOKEN_SECRET_OVERRIDE$PRIVATE_MODAL_PROXY_TOKEN_ID_OVERRIDE$PRIVATE_MODAL_PROXY_TOKEN_SECRET_OVERRIDE$PRIVATE_MODAL_MODEL_OVERRIDE$PRIVATE_MODAL_HF_MODEL_ID_OVERRIDE$PRIVATE_MODAL_CONTEXT_WINDOW_OVERRIDE$PRIVATE_MODAL_MAX_TOKENS_OVERRIDE$PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE$PRIVATE_MODAL_APP_NAME_OVERRIDE" || $PRIVATE_MODAL_SET_DEFAULT -eq 1 || $PRIVATE_MODAL_DISABLE -eq 1 || $PRIVATE_MODAL_DEPLOY -eq 1 || $PRIVATE_MODAL_SKIP_PREFETCH -eq 1 ]]; then
  die "--private-modal-* flags require --configure-private-modal-qwen"
fi

if (( PRIVATE_MODAL_DISABLE == 1 )) && [[ -n "$PRIVATE_MODAL_UPSTREAM_URL_OVERRIDE$PRIVATE_MODAL_TOKEN_ID_OVERRIDE$PRIVATE_MODAL_TOKEN_SECRET_OVERRIDE$PRIVATE_MODAL_PROXY_TOKEN_ID_OVERRIDE$PRIVATE_MODAL_PROXY_TOKEN_SECRET_OVERRIDE$PRIVATE_MODAL_MODEL_OVERRIDE$PRIVATE_MODAL_HF_MODEL_ID_OVERRIDE$PRIVATE_MODAL_CONTEXT_WINDOW_OVERRIDE$PRIVATE_MODAL_MAX_TOKENS_OVERRIDE$PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE$PRIVATE_MODAL_APP_NAME_OVERRIDE" || $PRIVATE_MODAL_SET_DEFAULT -eq 1 || $PRIVATE_MODAL_DEPLOY -eq 1 || $PRIVATE_MODAL_SKIP_PREFETCH -eq 1 ]]; then
  die "--disable-private-modal-qwen cannot be combined with other --private-modal-* configuration flags"
fi

if (( PRIVATE_MODAL_ENABLE == 1 && PRIVATE_MODAL_DISABLE == 0 )); then
  [[ "$PRIVATE_MODAL_CONTEXT_WINDOW_OVERRIDE" =~ ^[0-9]+$ || -z "$PRIVATE_MODAL_CONTEXT_WINDOW_OVERRIDE" ]] || die "--private-modal-context-window must be an integer"
  [[ "$PRIVATE_MODAL_MAX_TOKENS_OVERRIDE" =~ ^[0-9]+$ || -z "$PRIVATE_MODAL_MAX_TOKENS_OVERRIDE" ]] || die "--private-modal-max-tokens must be an integer"

  if (( PRIVATE_MODAL_DEPLOY == 0 )); then
    [[ -n "$PRIVATE_MODAL_UPSTREAM_URL_OVERRIDE" ]] || die "--private-modal-upstream-url is required with --configure-private-modal-qwen (unless --deploy-private-modal-qwen is used)"
  fi

  if [[ -n "$PRIVATE_MODAL_UPSTREAM_URL_OVERRIDE" || $PRIVATE_MODAL_SET_DEFAULT -eq 1 ]]; then
    [[ -n "$PRIVATE_MODAL_TOKEN_ID_OVERRIDE" ]] || die "--private-modal-token-id is required when configuring private modal proxy auth"
    [[ -n "$PRIVATE_MODAL_TOKEN_SECRET_OVERRIDE" ]] || die "--private-modal-token-secret is required when configuring private modal proxy auth"
  fi

  if [[ -n "$PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE" ]]; then
    [[ -f "$PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE" ]] || die "private modal HF token file not found: $PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE"
    hf_token_precheck=$(tr -d '\r\n' < "$PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE")
    [[ -n "$hf_token_precheck" ]] || die "private modal HF token file is empty: $PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE"
  elif (( PRIVATE_MODAL_DEPLOY == 1 && PRIVATE_MODAL_SKIP_PREFETCH == 0 )); then
    if [[ -n "${HF_TOKEN:-}${HUGGINGFACE_HUB_TOKEN:-}" ]]; then
      :
    elif [[ -t 0 ]]; then
      PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE=$(prompt_text "Hugging Face token file path (required for prefetch with gated/private models)" "")
      [[ -n "$PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE" ]] || die "--private-modal-hf-token-file is required for prefetch; pass --private-modal-skip-prefetch to bypass"
      [[ -f "$PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE" ]] || die "private modal HF token file not found: $PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE"
      hf_token_precheck=$(tr -d '\r\n' < "$PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE")
      [[ -n "$hf_token_precheck" ]] || die "private modal HF token file is empty: $PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE"
    else
      die "--private-modal-hf-token-file (or HF_TOKEN/HUGGINGFACE_HUB_TOKEN env) is required for non-interactive prefetch; or pass --private-modal-skip-prefetch"
    fi
  fi

fi

if (( SHELLEY_STATUS_ONLY )); then
  (( SHELLEY_REFRESH_ONLY == 0 )) || die "--print-shelley-mode-status cannot be combined with --refresh-shelley-mode"
  [[ -z "$STAVROBOT_DIR" ]] || die "--print-shelley-mode-status cannot be combined with --stavrobot-dir"
  (( REFRESH_ONLY == 0 && PLUGINS_ONLY == 0 && CONFIG_ONLY == 0 && SKIP_CONFIG == 0 && SKIP_PLUGINS == 0 && SHOW_SECRETS == 0 )) || \
    die "--print-shelley-mode-status cannot be combined with normal installer mutation flags"
  (( SHELLEY_ALLOW_DIRTY == 0 && SHELLEY_SKIP_SMOKE == 0 && SHELLEY_EXPECT_DISPLAY_DATA == 0 && SHELLEY_REQUIRE_DISPLAY_HINTS == 0 && SHELLEY_EXPECT_MEDIA_REFS == 0 && SHELLEY_REQUIRE_MEDIA_REFS == 0 && SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING == 0 && SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS == 0 && SHELLEY_EXPECT_RAW_MEDIA_REJECTION == 0 && SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS == 0 && SHELLEY_EXPECT_S2_MARKDOWN_TOOL_SUMMARY == 0 && SHELLEY_REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS == 0 && SHELLEY_EXPECT_S2_MARKDOWN_MEDIA_REFS == 0 && SHELLEY_REQUIRE_S2_MARKDOWN_MEDIA_REFS_HINTS == 0 && SHELLEY_EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK == 0 && SHELLEY_REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS == 0 && SHELLEY_STRICT_RAW_MEDIA_PROFILE == 0 && SHELLEY_S2_NARROW_FIDELITY_PROFILE == 0 && SHELLEY_MEMORY_SUITABILITY_GATE_PROFILE == 0 && SHELLEY_SYNC_UPSTREAM_FF_ONLY == 0 )) && [[ -z "$SHELLEY_BRIDGE_FIXTURE" ]] || \
    die "--print-shelley-mode-status cannot be combined with Shelley refresh-only flags"
else
  (( SHELLEY_STATUS_JSON == 0 )) || die "--json currently requires --print-shelley-mode-status"
  (( SHELLEY_STATUS_BASIC == 0 )) || die "--basic currently requires --print-shelley-mode-status"
fi

if (( SHELLEY_REFRESH_ONLY )); then
  [[ -z "$STAVROBOT_DIR" ]] || die "--refresh-shelley-mode cannot be combined with --stavrobot-dir"
  (( REFRESH_ONLY == 0 && PLUGINS_ONLY == 0 && CONFIG_ONLY == 0 && SKIP_CONFIG == 0 && SKIP_PLUGINS == 0 && SHOW_SECRETS == 0 )) || \
    die "--refresh-shelley-mode cannot be combined with normal installer mutation flags"
fi

if (( (SHELLEY_ALLOW_DIRTY || SHELLEY_SKIP_SMOKE || SHELLEY_EXPECT_DISPLAY_DATA || SHELLEY_REQUIRE_DISPLAY_HINTS || SHELLEY_EXPECT_MEDIA_REFS || SHELLEY_REQUIRE_MEDIA_REFS || SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING || SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS || SHELLEY_EXPECT_RAW_MEDIA_REJECTION || SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS || SHELLEY_EXPECT_S2_MARKDOWN_TOOL_SUMMARY || SHELLEY_REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS || SHELLEY_EXPECT_S2_MARKDOWN_MEDIA_REFS || SHELLEY_REQUIRE_S2_MARKDOWN_MEDIA_REFS_HINTS || SHELLEY_EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK || SHELLEY_REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS || SHELLEY_STRICT_RAW_MEDIA_PROFILE || SHELLEY_S2_NARROW_FIDELITY_PROFILE || SHELLEY_MEMORY_SUITABILITY_GATE_PROFILE || SHELLEY_SYNC_UPSTREAM_FF_ONLY) && SHELLEY_REFRESH_ONLY == 0 )) || ([[ -n "$SHELLEY_BRIDGE_FIXTURE" ]] && (( SHELLEY_REFRESH_ONLY == 0 ))); then
  die "--allow-dirty-shelley, --skip-shelley-smoke, --expect-shelley-display-data, --require-shelley-display-hints, --expect-shelley-media-refs, --require-shelley-media-refs, --expect-shelley-native-raw-media-gating, --require-shelley-native-raw-media-hints, --expect-shelley-raw-media-rejection, --require-shelley-raw-media-rejection-hints, --expect-shelley-s2-markdown-tool-summary, --require-shelley-s2-markdown-tool-summary-hints, --expect-shelley-s2-markdown-media-refs, --require-shelley-s2-markdown-media-refs-hints, --expect-shelley-s2-tool-summary-raw-fallback, --require-shelley-s2-tool-summary-raw-fallback-hints, --strict-shelley-raw-media-profile, --s2-shelley-narrow-fidelity-profile, --memory-suitability-gate-shelley-profile, --sync-shelley-upstream-ff-only, and --shelley-bridge-fixture require --refresh-shelley-mode"
fi
if (( SHELLEY_REQUIRE_DISPLAY_HINTS == 1 && SHELLEY_EXPECT_DISPLAY_DATA == 0 )); then
  die "--require-shelley-display-hints requires --expect-shelley-display-data"
fi
if (( SHELLEY_REQUIRE_MEDIA_REFS == 1 && SHELLEY_EXPECT_MEDIA_REFS == 0 )); then
  die "--require-shelley-media-refs requires --expect-shelley-media-refs"
fi
if (( SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS == 1 && SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING == 0 )); then
  die "--require-shelley-native-raw-media-hints requires --expect-shelley-native-raw-media-gating"
fi
if (( SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS == 1 && SHELLEY_EXPECT_RAW_MEDIA_REJECTION == 0 )); then
  die "--require-shelley-raw-media-rejection-hints requires --expect-shelley-raw-media-rejection"
fi
if (( SHELLEY_REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS == 1 && SHELLEY_EXPECT_S2_MARKDOWN_TOOL_SUMMARY == 0 )); then
  die "--require-shelley-s2-markdown-tool-summary-hints requires --expect-shelley-s2-markdown-tool-summary"
fi
if (( SHELLEY_REQUIRE_S2_MARKDOWN_MEDIA_REFS_HINTS == 1 && SHELLEY_EXPECT_S2_MARKDOWN_MEDIA_REFS == 0 )); then
  die "--require-shelley-s2-markdown-media-refs-hints requires --expect-shelley-s2-markdown-media-refs"
fi
if (( SHELLEY_REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS == 1 && SHELLEY_EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK == 0 )); then
  die "--require-shelley-s2-tool-summary-raw-fallback-hints requires --expect-shelley-s2-tool-summary-raw-fallback"
fi
if (( SHELLEY_STRICT_RAW_MEDIA_PROFILE == 1 )); then
  if (( SHELLEY_EXPECT_DISPLAY_DATA == 1 || SHELLEY_REQUIRE_DISPLAY_HINTS == 1 || SHELLEY_EXPECT_MEDIA_REFS == 1 || SHELLEY_REQUIRE_MEDIA_REFS == 1 || SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING == 1 || SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS == 1 || SHELLEY_EXPECT_RAW_MEDIA_REJECTION == 1 || SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS == 1 || SHELLEY_EXPECT_S2_MARKDOWN_TOOL_SUMMARY == 1 || SHELLEY_REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS == 1 || SHELLEY_EXPECT_S2_MARKDOWN_MEDIA_REFS == 1 || SHELLEY_REQUIRE_S2_MARKDOWN_MEDIA_REFS_HINTS == 1 || SHELLEY_EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK == 1 || SHELLEY_REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS == 1 )) || [[ -n "$SHELLEY_BRIDGE_FIXTURE" ]]; then
    die "--strict-shelley-raw-media-profile cannot be combined with explicit --expect/--require Shelley smoke flags or --shelley-bridge-fixture"
  fi
fi
if (( SHELLEY_S2_NARROW_FIDELITY_PROFILE == 1 )); then
  if (( SHELLEY_EXPECT_DISPLAY_DATA == 1 || SHELLEY_REQUIRE_DISPLAY_HINTS == 1 || SHELLEY_EXPECT_MEDIA_REFS == 1 || SHELLEY_REQUIRE_MEDIA_REFS == 1 || SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING == 1 || SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS == 1 || SHELLEY_EXPECT_RAW_MEDIA_REJECTION == 1 || SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS == 1 || SHELLEY_EXPECT_S2_MARKDOWN_TOOL_SUMMARY == 1 || SHELLEY_REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS == 1 || SHELLEY_EXPECT_S2_MARKDOWN_MEDIA_REFS == 1 || SHELLEY_REQUIRE_S2_MARKDOWN_MEDIA_REFS_HINTS == 1 || SHELLEY_EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK == 1 || SHELLEY_REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS == 1 )) || [[ -n "$SHELLEY_BRIDGE_FIXTURE" ]]; then
    die "--s2-shelley-narrow-fidelity-profile cannot be combined with explicit --expect/--require Shelley smoke flags or --shelley-bridge-fixture"
  fi
fi
if (( SHELLEY_STRICT_RAW_MEDIA_PROFILE == 1 && SHELLEY_S2_NARROW_FIDELITY_PROFILE == 1 )); then
  die "--strict-shelley-raw-media-profile cannot be combined with --s2-shelley-narrow-fidelity-profile"
fi
if (( SHELLEY_MEMORY_SUITABILITY_GATE_PROFILE == 1 )); then
  if (( SHELLEY_EXPECT_DISPLAY_DATA == 1 || SHELLEY_REQUIRE_DISPLAY_HINTS == 1 || SHELLEY_EXPECT_MEDIA_REFS == 1 || SHELLEY_REQUIRE_MEDIA_REFS == 1 || SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING == 1 || SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS == 1 || SHELLEY_EXPECT_RAW_MEDIA_REJECTION == 1 || SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS == 1 || SHELLEY_EXPECT_S2_MARKDOWN_TOOL_SUMMARY == 1 || SHELLEY_REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS == 1 || SHELLEY_EXPECT_S2_MARKDOWN_MEDIA_REFS == 1 || SHELLEY_REQUIRE_S2_MARKDOWN_MEDIA_REFS_HINTS == 1 || SHELLEY_EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK == 1 || SHELLEY_REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS == 1 )) || [[ -n "$SHELLEY_BRIDGE_FIXTURE" ]]; then
    die "--memory-suitability-gate-shelley-profile cannot be combined with explicit --expect/--require Shelley smoke flags or --shelley-bridge-fixture"
  fi
fi
if (( SHELLEY_MEMORY_SUITABILITY_GATE_PROFILE == 1 && SHELLEY_STRICT_RAW_MEDIA_PROFILE == 1 )); then
  die "--memory-suitability-gate-shelley-profile cannot be combined with --strict-shelley-raw-media-profile"
fi
if (( SHELLEY_MEMORY_SUITABILITY_GATE_PROFILE == 1 && SHELLEY_S2_NARROW_FIDELITY_PROFILE == 1 )); then
  die "--memory-suitability-gate-shelley-profile cannot be combined with --s2-shelley-narrow-fidelity-profile"
fi

if (( DOCTOR_ONLY )); then
  run_doctor "$DOCTOR_JSON"
  exit 0
fi

if (( CF_EMAIL_WORKER_ONLY )); then
  [[ -n "$STAVROBOT_DIR" ]] || die "--configure-cloudflare-email-worker requires --stavrobot-dir"
  (( REFRESH_ONLY == 0 && PLUGINS_ONLY == 0 && CONFIG_ONLY == 0 && SKIP_CONFIG == 0 && SKIP_PLUGINS == 0 && SHELLEY_STATUS_ONLY == 0 && SHELLEY_REFRESH_ONLY == 0 && EXEDEV_EMAIL_BRIDGE_ONLY == 0 )) || \
    die "--configure-cloudflare-email-worker cannot be combined with installer mutation/status/refresh flags"
  cf_args=(--stavrobot-dir "$STAVROBOT_DIR")
  if (( CF_EMAIL_WORKER_DEPLOY )); then
    cf_args+=(--deploy)
  fi
  if [[ -n "$CF_EMAIL_WORKER_NAME" ]]; then
    cf_args+=(--worker-name "$CF_EMAIL_WORKER_NAME")
  fi
  if [[ -n "$CF_EMAIL_WORKER_ACCOUNT_ID" ]]; then
    cf_args+=(--account-id "$CF_EMAIL_WORKER_ACCOUNT_ID")
  fi
  "$ROOT_DIR/install-cloudflare-email-worker.sh" "${cf_args[@]}"

  cat <<'EOF'

[manual-cloudflare-steps]
You still need to complete one Cloudflare portal step:
  1) Cloudflare Dashboard -> Email -> Email Routing
  2) Route inbound mail to the deployed worker (default: stavrobot-email-worker)
  3) Send a test email and verify Stavrobot receives /email/webhook
EOF
  exit 0
fi

if (( EXEDEV_EMAIL_BRIDGE_ONLY )); then
  [[ -n "$STAVROBOT_DIR" ]] || die "--configure-exedev-email-bridge requires --stavrobot-dir"
  (( REFRESH_ONLY == 0 && PLUGINS_ONLY == 0 && CONFIG_ONLY == 0 && SKIP_CONFIG == 0 && SKIP_PLUGINS == 0 && SHELLEY_STATUS_ONLY == 0 && SHELLEY_REFRESH_ONLY == 0 && CF_EMAIL_WORKER_ONLY == 0 && CF_EMAIL_WORKER_DEPLOY == 0 && PRIVATE_MODAL_ENABLE == 0 )) || \
    die "--configure-exedev-email-bridge cannot be combined with installer mutation/status/refresh flags"
  exedev_args=(--stavrobot-dir "$STAVROBOT_DIR")
  if (( EXEDEV_EMAIL_BRIDGE_DISABLE )); then
    exedev_args+=(--disable-service)
  fi
  "$ROOT_DIR/install-exedev-email-bridge.sh" "${exedev_args[@]}"

  cat <<'EOF'

[manual-exedev-email-steps]
You still need one exe.dev CLI step (outside this installer):
  1) ssh exe.dev share receive-email <vmname> on
  2) Send a test email to any.address@<vmname>.exe.xyz
  3) Verify bridge logs and Stavrobot /email/webhook handling
EOF
  exit 0
fi

if (( PRIVATE_MODAL_ENABLE )); then
  [[ -n "$STAVROBOT_DIR" ]] || die "--configure-private-modal-qwen requires --stavrobot-dir"

  require_cmd git
  require_cmd python3
  require_cmd docker
  require_cmd curl
  ensure_stavrobot_checkout "$STAVROBOT_DIR" "$STAVROBOT_REPO_URL"

  if [[ -f "$STAVROBOT_DIR/data/main/config.toml" || -d "$STAVROBOT_DIR/data/main" ]]; then
    CONFIG_PATH="$STAVROBOT_DIR/data/main/config.toml"
  elif [[ -f "$STAVROBOT_DIR/config/config.toml" || -d "$STAVROBOT_DIR/config" ]]; then
    CONFIG_PATH="$STAVROBOT_DIR/config/config.toml"
  else
    CONFIG_PATH="$STAVROBOT_DIR/data/main/config.toml"
  fi
  (( REFRESH_ONLY == 0 && PLUGINS_ONLY == 0 && SKIP_CONFIG == 0 && SKIP_PLUGINS == 0 && SHELLEY_STATUS_ONLY == 0 && SHELLEY_REFRESH_ONLY == 0 && CF_EMAIL_WORKER_ONLY == 0 && CF_EMAIL_WORKER_DEPLOY == 0 && EXEDEV_EMAIL_BRIDGE_ONLY == 0 )) || \
    die "--configure-private-modal-qwen cannot be combined with installer mutation/status/refresh flags"

  if (( PRIVATE_MODAL_DISABLE )); then
    remove_private_modal_llm_override "$STAVROBOT_DIR"
    info "Removed private Modal proxy override file"
    if (( CONFIG_ONLY == 0 )); then
      info "Recreating containers after private Modal disable"
      docker_compose_up_recreate "$STAVROBOT_DIR"
      load_runtime_metadata
      if [[ -n "$PASSWORD_FOR_READY" ]]; then
        wait_for_stavrobot_ready
      fi
    fi
    exit 0
  fi

  modal_hf_model_id="${PRIVATE_MODAL_HF_MODEL_ID_OVERRIDE:-Qwen/Qwen3.5-9B}"
  modal_model="${PRIVATE_MODAL_MODEL_OVERRIDE:-$modal_hf_model_id}"
  modal_context_window="${PRIVATE_MODAL_CONTEXT_WINDOW_OVERRIDE:-8192}"
  modal_max_tokens="${PRIVATE_MODAL_MAX_TOKENS_OVERRIDE:-8192}"
  modal_app_name="${PRIVATE_MODAL_APP_NAME_OVERRIDE:-private-modal-qwen35-9b}"
  modal_app_script="$ROOT_DIR/scripts/modal_qwen35_9b_app.py"
  modal_app_script_for_deploy="$modal_app_script"

  if (( PRIVATE_MODAL_DEPLOY )); then
    require_cmd python3

    MODAL_BIN=""
    if command -v modal >/dev/null 2>&1; then
      MODAL_BIN=$(command -v modal)
    else
      ensure_python_venv_capable
      modal_venv="$ROOT_DIR/state/modal-cli-venv"
      if [[ ! -x "$modal_venv/bin/modal" ]]; then
        info "Installing Modal CLI into isolated venv: $modal_venv"
        python3 -m venv "$modal_venv"
        "$modal_venv/bin/pip" install -q modal
      fi
      MODAL_BIN="$modal_venv/bin/modal"
    fi

    [[ -x "$MODAL_BIN" ]] || die "Modal CLI not found; install with pipx or provide modal in PATH"

    if [[ "$modal_app_name" != "private-modal-qwen35-9b" || "$modal_hf_model_id" != "Qwen/Qwen3.5-9B" ]]; then
      modal_tmp_script=$(mktemp /tmp/modal_qwen35_9b_app_override_XXXXXX.py)
      python3 - "$modal_app_script" "$modal_tmp_script" "$modal_app_name" "$modal_hf_model_id" "$modal_context_window" <<'PY'
import pathlib, re, sys
src, dst, app_name, model_id, max_model_len = sys.argv[1:]
text = pathlib.Path(src).read_text()
text = re.sub(r'APP_NAME\s*=\s*"[^"]+"', f'APP_NAME = "{app_name}"', text, count=1)
text = re.sub(r'MODEL_ID\s*=\s*"[^"]+"', f'MODEL_ID = "{model_id}"', text, count=1)
text = re.sub(r'MAX_MODEL_LEN\s*=\s*int\(os\.environ\.get\("MAX_MODEL_LEN",\s*"[0-9]+"\)\)',
              f'MAX_MODEL_LEN = int(os.environ.get("MAX_MODEL_LEN", "{max_model_len}"))', text, count=1)
pathlib.Path(dst).write_text(text)
print(dst)
PY
      modal_app_script_for_deploy="$modal_tmp_script"
    fi

    hf_token_value="${HF_TOKEN:-${HUGGINGFACE_HUB_TOKEN:-}}"
    if [[ -n "$PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE" ]]; then
      [[ -f "$PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE" ]] || die "private modal HF token file not found: $PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE"
      hf_token_value=$(tr -d '\r\n' < "$PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE")
      [[ -n "$hf_token_value" ]] || die "private modal HF token file is empty: $PRIVATE_MODAL_HF_TOKEN_FILE_OVERRIDE"
    fi

    if (( PRIVATE_MODAL_SKIP_PREFETCH == 0 )); then
      info "Running one-time Modal model prefetch into persistent volume"
      if [[ -n "${hf_token_value:-}" ]]; then
        "$MODAL_BIN" run "$modal_app_script_for_deploy"::prefetch_model --hf-token "$hf_token_value"
      else
        "$MODAL_BIN" run "$modal_app_script_for_deploy"::prefetch_model
      fi
    fi

    info "Deploying Modal app via CLI"
    deploy_log=$(mktemp)
    if ! "$MODAL_BIN" deploy "$modal_app_script_for_deploy" 2>&1 | tee "$deploy_log"; then
      rm -f "$deploy_log"
      die "Modal deploy failed"
    fi

    detected_url=$(python3 - "$deploy_log" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
urls = re.findall(r'https://[a-zA-Z0-9\-\.]+\.modal\.run', text)
print(urls[-1] if urls else '')
PY
)
    rm -f "$deploy_log"

    if [[ -n "$detected_url" ]]; then
      PRIVATE_MODAL_UPSTREAM_URL_OVERRIDE="$detected_url"
      info "Detected Modal endpoint URL: $PRIVATE_MODAL_UPSTREAM_URL_OVERRIDE"
    fi

    [[ -n "$PRIVATE_MODAL_UPSTREAM_URL_OVERRIDE" ]] || die "Could not auto-detect Modal endpoint URL. Re-run with --private-modal-upstream-url"
    if [[ -n "${modal_tmp_script:-}" ]]; then
      rm -f "$modal_tmp_script"
    fi
  fi

  [[ -n "$PRIVATE_MODAL_UPSTREAM_URL_OVERRIDE" ]] || die "Missing private modal upstream URL"
  [[ -n "$PRIVATE_MODAL_TOKEN_ID_OVERRIDE" ]] || die "Missing private modal token id"
  [[ -n "$PRIVATE_MODAL_TOKEN_SECRET_OVERRIDE" ]] || die "Missing private modal token secret"

  write_private_modal_llm_override "$STAVROBOT_DIR" "$ROOT_DIR/scripts/modal_openai_proxy.py" "$PRIVATE_MODAL_UPSTREAM_URL_OVERRIDE" "$PRIVATE_MODAL_TOKEN_ID_OVERRIDE" "$PRIVATE_MODAL_TOKEN_SECRET_OVERRIDE" "11435"
  write_private_modal_profile_state "$PRIVATE_MODAL_UPSTREAM_URL_OVERRIDE" "$PRIVATE_MODAL_TOKEN_ID_OVERRIDE" "$PRIVATE_MODAL_TOKEN_SECRET_OVERRIDE" "$modal_model" "$modal_context_window" "$modal_max_tokens"
  info "Private Modal proxy override written"

  if (( PRIVATE_MODAL_SET_DEFAULT )); then
    seeded_missing_config=0
    if [[ ! -f "$CONFIG_PATH" ]]; then
      mkdir -p "$(dirname "$CONFIG_PATH")"
      if [[ -f "$STAVROBOT_DIR/config.example.toml" ]]; then
        cp "$STAVROBOT_DIR/config.example.toml" "$CONFIG_PATH"
        info "Seeded missing config from config.example.toml at $CONFIG_PATH"
        seeded_missing_config=1
      else
        die "Missing config.toml at $CONFIG_PATH"
      fi
    fi
    apply_private_modal_profile_to_config "$modal_model" "$modal_context_window" "$modal_max_tokens"
    strip_seeded_telegram_config_if_disabled "$CONFIG_PATH"
    info "Set Stavrobot default provider/model to private Modal profile"
  fi

  if (( CONFIG_ONLY == 0 )); then
    info "Recreating containers after private Modal configure"
    docker_compose_up_recreate "$STAVROBOT_DIR"
    load_runtime_metadata
    wait_for_stavrobot_ready
  fi

  cat <<EOF

[private-modal-next-steps]
- Private Modal local proxy service override is configured.
- Stored profile metadata: $ROOT_DIR/state/llm-profiles.json
- Modal app script: $modal_app_script (app name: $modal_app_name)
- If Modal CLI is not authenticated yet, run: modal setup
- To disable later:
  ./install-stavrobot.sh --configure-private-modal-qwen --disable-private-modal-qwen --stavrobot-dir "$STAVROBOT_DIR"
EOF
  exit 0
fi

if (( SHELLEY_STATUS_ONLY )); then
  status_args=(--shelley-dir "$MANAGED_SHELLEY_DIR")
  if (( SHELLEY_STATUS_JSON )); then
    status_args+=(--json)
  fi
  if (( SHELLEY_STATUS_BASIC )); then
    status_args+=(--basic)
  fi
  exec "$ROOT_DIR/print-shelley-managed-status.sh" "${status_args[@]}"
fi

if (( SHELLEY_REFRESH_ONLY )); then
  refresh_args=(--shelley-dir "$MANAGED_SHELLEY_DIR" --profile-state-path /var/lib/stavrobot-installer/shelley-bridge-profiles.json)
  if (( SHELLEY_ALLOW_DIRTY )); then
    refresh_args+=(--allow-dirty)
  fi
  if (( SHELLEY_SKIP_SMOKE )); then
    refresh_args+=(--skip-smoke)
  fi
  if (( SHELLEY_EXPECT_DISPLAY_DATA )); then
    refresh_args+=(--smoke-expect-display-data)
  fi
  if (( SHELLEY_REQUIRE_DISPLAY_HINTS )); then
    refresh_args+=(--smoke-require-display-hints)
  fi
  if (( SHELLEY_EXPECT_MEDIA_REFS )); then
    refresh_args+=(--smoke-expect-media-refs)
  fi
  if (( SHELLEY_REQUIRE_MEDIA_REFS )); then
    refresh_args+=(--smoke-require-media-refs)
  fi
  if (( SHELLEY_EXPECT_NATIVE_RAW_MEDIA_GATING )); then
    refresh_args+=(--smoke-expect-native-raw-media-gating)
  fi
  if (( SHELLEY_REQUIRE_NATIVE_RAW_MEDIA_HINTS )); then
    refresh_args+=(--smoke-require-native-raw-media-hints)
  fi
  if (( SHELLEY_EXPECT_RAW_MEDIA_REJECTION )); then
    refresh_args+=(--smoke-expect-raw-media-rejection)
  fi
  if (( SHELLEY_REQUIRE_RAW_MEDIA_REJECTION_HINTS )); then
    refresh_args+=(--smoke-require-raw-media-rejection-hints)
  fi
  if (( SHELLEY_EXPECT_S2_MARKDOWN_TOOL_SUMMARY )); then
    refresh_args+=(--smoke-expect-s2-markdown-tool-summary)
  fi
  if (( SHELLEY_REQUIRE_S2_MARKDOWN_TOOL_SUMMARY_HINTS )); then
    refresh_args+=(--smoke-require-s2-markdown-tool-summary-hints)
  fi
  if (( SHELLEY_EXPECT_S2_MARKDOWN_MEDIA_REFS )); then
    refresh_args+=(--smoke-expect-s2-markdown-media-refs)
  fi
  if (( SHELLEY_REQUIRE_S2_MARKDOWN_MEDIA_REFS_HINTS )); then
    refresh_args+=(--smoke-require-s2-markdown-media-refs-hints)
  fi
  if (( SHELLEY_EXPECT_S2_TOOL_SUMMARY_RAW_FALLBACK )); then
    refresh_args+=(--smoke-expect-s2-tool-summary-raw-fallback)
  fi
  if (( SHELLEY_REQUIRE_S2_TOOL_SUMMARY_RAW_FALLBACK_HINTS )); then
    refresh_args+=(--smoke-require-s2-tool-summary-raw-fallback-hints)
  fi
  if [[ -n "$SHELLEY_BRIDGE_FIXTURE" ]]; then
    refresh_args+=(--smoke-bridge-fixture "$SHELLEY_BRIDGE_FIXTURE")
  fi
  if (( SHELLEY_STRICT_RAW_MEDIA_PROFILE )); then
    refresh_args+=(--smoke-strict-raw-media-profile)
  fi
  if (( SHELLEY_S2_NARROW_FIDELITY_PROFILE )); then
    refresh_args+=(--smoke-s2-narrow-fidelity-profile)
  fi
  if (( SHELLEY_MEMORY_SUITABILITY_GATE_PROFILE )); then
    refresh_args+=(--smoke-memory-suitability-gate-profile)
  fi
  if (( SHELLEY_SYNC_UPSTREAM_FF_ONLY )); then
    refresh_args+=(--sync-upstream-ff-only)
  fi
  exec "$ROOT_DIR/refresh-shelley-managed-s1.sh" "${refresh_args[@]}"
fi

[[ -n "$STAVROBOT_DIR" ]] || die "--stavrobot-dir is required"

require_cmd git
require_cmd python3
require_cmd docker
require_cmd curl

ensure_stavrobot_checkout "$STAVROBOT_DIR" "$STAVROBOT_REPO_URL"
mkdir -p "$ROOT_DIR/state"
ENV_PATH="$STAVROBOT_DIR/.env"
if [[ -f "$STAVROBOT_DIR/data/main/config.toml" || -d "$STAVROBOT_DIR/data/main" ]]; then
  CONFIG_PATH="$STAVROBOT_DIR/data/main/config.toml"
elif [[ -f "$STAVROBOT_DIR/config/config.toml" || -d "$STAVROBOT_DIR/config" ]]; then
  CONFIG_PATH="$STAVROBOT_DIR/config/config.toml"
else
  CONFIG_PATH="$STAVROBOT_DIR/data/main/config.toml"
fi
PLUGIN_STATE_JSON="$ROOT_DIR/state/last-plugin-inputs.json"
PLUGIN_REPORT_FILE="$ROOT_DIR/state/last-plugin-report.txt"
: > "$PLUGIN_REPORT_FILE"
mkdir -p "$(dirname "$CONFIG_PATH")"

info "Documented plan: $ROOT_DIR/IMPLEMENTATION_PLAN.md"
info "Validating upstream stavrobot repo"
BEFORE_HEAD=$(get_repo_head "$STAVROBOT_DIR")
if (( CONFIG_ONLY || SKIP_CONFIG )); then
  AFTER_HEAD="$BEFORE_HEAD"
  info "Config-only path: skipping upstream stavrobot pull"
else
  check_repo_clean_for_pull "$STAVROBOT_DIR"
  pull_latest_stavrobot "$STAVROBOT_DIR"
  AFTER_HEAD=$(get_repo_head "$STAVROBOT_DIR")

  if [[ "$BEFORE_HEAD" != "$AFTER_HEAD" ]]; then
    info "Updated stavrobot from $BEFORE_HEAD to $AFTER_HEAD"
  else
    info "Stavrobot already up to date at $AFTER_HEAD"
  fi
fi

if (( !PLUGINS_ONLY )) && [[ -z "${SHELLEY_INSTALLER_TEST_SKIP_OPENROUTER_FETCH:-}" ]]; then
  fetch_openrouter_suggestions || true
fi

if (( PLUGINS_ONLY )); then
  load_runtime_metadata
  [[ -f "$PLUGIN_STATE_JSON" ]] || die "No saved plugin state at $PLUGIN_STATE_JSON"
  wait_for_stavrobot_ready
  run_plugins_from_state
  print_run_summary "$BEFORE_HEAD" "$AFTER_HEAD" false false 0 "$PLUGINS_HANDLED" "$PLUGIN_REPORT_FILE"
  print_next_steps "$PUBLIC_HOSTNAME_FINAL" "$CODER_ENABLED" "$SIGNAL_ENABLED" "$WHATSAPP_ENABLED" "$EMAIL_ENABLED" "$AUTH_MODE_FINAL" "$EMAIL_TRANSPORT_MODE"
  exit 0
fi

BEFORE_ENV_HASH=$(sha256_file "$ENV_PATH")
BEFORE_CONFIG_HASH=$(sha256_file "$CONFIG_PATH")

if (( REFRESH_ONLY )); then
  info "Refresh mode: skipping config prompts"
  load_runtime_metadata
elif (( SKIP_CONFIG )); then
  info "Skip-config mode: reusing existing config files"
  load_runtime_metadata
else
  render_current_state

  ENV_EXAMPLE_TZ=$(json_get "$CURRENT_JSON" env_example.TZ)
  ENV_CURRENT_TZ=$(json_get "$CURRENT_JSON" env_current.TZ)
  TZ_DEFAULT=${ENV_CURRENT_TZ:-$ENV_EXAMPLE_TZ}
  TZ_VALUE=$(prompt_text "Timezone" "$TZ_DEFAULT")
  TZ_VALUE=${TZ_VALUE:-$TZ_DEFAULT}

  if prompt_yes_no "Review advanced Postgres env overrides?" "N"; then
    PG_USER_DEFAULT=$(json_get "$CURRENT_JSON" env_current.POSTGRES_USER)
    PG_USER_DEFAULT=${PG_USER_DEFAULT:-$(json_get "$CURRENT_JSON" env_example.POSTGRES_USER)}
    PG_USER=$(prompt_text "Postgres username" "$PG_USER_DEFAULT")
    PG_USER=${PG_USER:-$PG_USER_DEFAULT}

    PG_PASSWORD_DEFAULT=$(json_get "$CURRENT_JSON" env_current.POSTGRES_PASSWORD)
    PG_PASSWORD_DEFAULT=${PG_PASSWORD_DEFAULT:-$(json_get "$CURRENT_JSON" env_example.POSTGRES_PASSWORD)}
    if (( SHOW_SECRETS )); then
      PG_PASSWORD=$(prompt_secret "Postgres password" "$PG_PASSWORD_DEFAULT")
    else
      PG_PASSWORD=$(prompt_secret "Postgres password" "$(mask_secret "$PG_PASSWORD_DEFAULT")")
    fi
    PG_PASSWORD=${PG_PASSWORD:-$PG_PASSWORD_DEFAULT}

    PG_DB_DEFAULT=$(json_get "$CURRENT_JSON" env_current.POSTGRES_DB)
    PG_DB_DEFAULT=${PG_DB_DEFAULT:-$(json_get "$CURRENT_JSON" env_example.POSTGRES_DB)}
    PG_DB=$(prompt_text "Postgres database name" "$PG_DB_DEFAULT")
    PG_DB=${PG_DB:-$PG_DB_DEFAULT}
  else
    PG_USER=$(json_get "$CURRENT_JSON" env_example.POSTGRES_USER)
    PG_PASSWORD=$(json_get "$CURRENT_JSON" env_example.POSTGRES_PASSWORD)
    PG_DB=$(json_get "$CURRENT_JSON" env_example.POSTGRES_DB)
  fi

  PROVIDER_MODE=$(prompt_choice "Provider setup:" "Anthropic" "OpenRouter" "OpenAI-compatible" "Manual/custom")

  PROVIDER=""
  MODEL=""
  API_KEY=""
  AUTH_FILE=""
  OWNER_NAME_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.name)
  OWNER_NAME_DEFAULT=${OWNER_NAME_DEFAULT:-$(json_get "$CURRENT_JSON" toml_example.owner.name)}

  case "$PROVIDER_MODE" in
    Anthropic)
      PROVIDER="anthropic"
      AUTH_MODE=$(prompt_choice "Anthropic auth mode:" "API key" "authFile")
      AUTH_MODE_FINAL=$([[ "$AUTH_MODE" == "API key" ]] && echo apiKey || echo authFile)
      MODEL_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.model)
      MODEL_DEFAULT=${MODEL_DEFAULT:-$(json_get "$CURRENT_JSON" toml_example.model)}
      MODEL=$(prompt_text "Anthropic model" "$MODEL_DEFAULT")
      MODEL=${MODEL:-$MODEL_DEFAULT}
      if [[ "$AUTH_MODE" == "API key" ]]; then
        API_KEY_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.apiKey)
        if (( SHOW_SECRETS )); then
          API_KEY=$(prompt_secret "Anthropic API key" "$API_KEY_DEFAULT")
        else
          API_KEY=$(prompt_secret "Anthropic API key" "$(mask_secret "$API_KEY_DEFAULT")")
        fi
        API_KEY=${API_KEY:-$API_KEY_DEFAULT}
        [[ -n "$API_KEY" ]] || die "Anthropic API key is required when using API key auth"
      else
        AUTH_FILE_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.authFile)
        AUTH_FILE_DEFAULT=${AUTH_FILE_DEFAULT:-/app/data/auth.json}
        AUTH_FILE=$(prompt_text "Auth file path" "$AUTH_FILE_DEFAULT")
        AUTH_FILE=${AUTH_FILE:-$AUTH_FILE_DEFAULT}
        [[ -n "$AUTH_FILE" ]] || die "authFile path is required when using authFile auth"
      fi
      ;;
    OpenRouter)
      PROVIDER="openrouter"
      AUTH_MODE=$(prompt_choice "OpenRouter auth mode:" "API key" "authFile")
      AUTH_MODE_FINAL=$([[ "$AUTH_MODE" == "API key" ]] && echo apiKey || echo authFile)
      MODEL_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.model)
      if [[ "$(json_get "$CURRENT_JSON" toml_current.provider)" != "openrouter" ]]; then
        MODEL_DEFAULT="openrouter/free"
      fi
      MODEL=$(prompt_openrouter_model "$MODEL_DEFAULT")
      if [[ "$AUTH_MODE" == "API key" ]]; then
        API_KEY_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.apiKey)
        if (( SHOW_SECRETS )); then
          API_KEY=$(prompt_secret "OpenRouter API key" "$API_KEY_DEFAULT")
        else
          API_KEY=$(prompt_secret "OpenRouter API key" "$(mask_secret "$API_KEY_DEFAULT")")
        fi
        API_KEY=${API_KEY:-$API_KEY_DEFAULT}
        [[ -n "$API_KEY" ]] || die "OpenRouter API key is required when using API key auth"
      else
        AUTH_FILE_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.authFile)
        AUTH_FILE_DEFAULT=${AUTH_FILE_DEFAULT:-/app/data/auth.json}
        AUTH_FILE=$(prompt_text "OpenRouter auth file path" "$AUTH_FILE_DEFAULT")
        AUTH_FILE=${AUTH_FILE:-$AUTH_FILE_DEFAULT}
        [[ -n "$AUTH_FILE" ]] || die "OpenRouter authFile path is required when using authFile auth"
      fi
      ;;
    OpenAI-compatible)
      warn "Current upstream stavrobot config exposes provider and model, but no explicit base URL field. Arbitrary OpenAI-compatible setups may require upstream support beyond this installer."
      AUTH_MODE_FINAL=apiKey
      PROVIDER_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.provider)
      PROVIDER=$(prompt_text "Provider label" "$PROVIDER_DEFAULT")
      MODEL=$(prompt_text "Model ID" "")
      API_KEY=$(prompt_secret "API key" "")
      [[ -n "$PROVIDER" ]] || die "Provider label is required"
      [[ -n "$MODEL" ]] || die "Model ID is required"
      [[ -n "$API_KEY" ]] || die "API key is required"
      ;;
    Manual/custom)
      PROVIDER_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.provider)
      PROVIDER=$(prompt_text "Provider label" "$PROVIDER_DEFAULT")
      MODEL_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.model)
      MODEL=$(prompt_text "Model ID" "$MODEL_DEFAULT")
      MODEL=${MODEL:-$MODEL_DEFAULT}
      API_KEY=$(prompt_secret "API key (or leave blank to use authFile)" "")
      if [[ -z "$API_KEY" ]]; then
        AUTH_FILE_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.authFile)
        AUTH_FILE=$(prompt_text "Auth file path" "$AUTH_FILE_DEFAULT")
        AUTH_FILE=${AUTH_FILE:-$AUTH_FILE_DEFAULT}
        AUTH_MODE_FINAL=authFile
      else
        AUTH_MODE_FINAL=apiKey
      fi
      [[ -n "$PROVIDER" ]] || die "Provider label is required"
      [[ -n "$MODEL" ]] || die "Model ID is required"
      [[ -n "$API_KEY" || -n "$AUTH_FILE" ]] || die "Either API key or authFile is required"
      ;;
  esac

  PASSWORD_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.password)
  PASSWORD_DEFAULT=${PASSWORD_DEFAULT:-change-me}
  if (( SHOW_SECRETS )); then
    PASSWORD=$(prompt_secret "HTTP basic auth password" "$PASSWORD_DEFAULT")
  else
    PASSWORD=$(prompt_secret "HTTP basic auth password" "$(mask_secret "$PASSWORD_DEFAULT")")
  fi
  PASSWORD=${PASSWORD:-$PASSWORD_DEFAULT}

  PUBLIC_HOSTNAME_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.publicHostname)
  PUBLIC_HOSTNAME_DEFAULT=${PUBLIC_HOSTNAME_DEFAULT:-https://example.com}
  PUBLIC_HOSTNAME=$(prompt_text "Public HTTPS URL" "$PUBLIC_HOSTNAME_DEFAULT")
  PUBLIC_HOSTNAME=${PUBLIC_HOSTNAME:-$PUBLIC_HOSTNAME_DEFAULT}
  PUBLIC_HOSTNAME=${PUBLIC_HOSTNAME%/}
  [[ "$PUBLIC_HOSTNAME" =~ ^https?:// ]] || die "publicHostname must start with http:// or https://"
  PUBLIC_HOSTNAME_FINAL="$PUBLIC_HOSTNAME"

  OWNER_NAME=$(prompt_text "Owner name" "$OWNER_NAME_DEFAULT")
  OWNER_NAME=${OWNER_NAME:-$OWNER_NAME_DEFAULT}
  [[ -n "$OWNER_NAME" ]] || die "Owner name is required by stavrobot"

  OWNER_SIGNAL_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.signal)
  OWNER_SIGNAL=$(prompt_optional_text "Owner Signal number (optional; type SKIP to omit)" "$OWNER_SIGNAL_DEFAULT")
  [[ "$OWNER_SIGNAL" == "__SKIP__" ]] && OWNER_SIGNAL=""
  OWNER_SIGNAL=${OWNER_SIGNAL:-$OWNER_SIGNAL_DEFAULT}

  OWNER_TELEGRAM_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.telegram)
  OWNER_TELEGRAM=$(prompt_optional_text "Owner Telegram chat ID (optional; type SKIP to omit)" "$OWNER_TELEGRAM_DEFAULT")
  [[ "$OWNER_TELEGRAM" == "__SKIP__" ]] && OWNER_TELEGRAM=""
  OWNER_TELEGRAM=${OWNER_TELEGRAM:-$OWNER_TELEGRAM_DEFAULT}

  OWNER_WHATSAPP_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.whatsapp)
  OWNER_WHATSAPP=$(prompt_optional_text "Owner WhatsApp number (optional; type SKIP to omit)" "$OWNER_WHATSAPP_DEFAULT")
  [[ "$OWNER_WHATSAPP" == "__SKIP__" ]] && OWNER_WHATSAPP=""
  OWNER_WHATSAPP=${OWNER_WHATSAPP:-$OWNER_WHATSAPP_DEFAULT}

  OWNER_EMAIL_DEFAULT=$(json_get "$CURRENT_JSON" toml_current.owner.email)
  OWNER_EMAIL=$(prompt_optional_text "Owner email address (optional; type SKIP to omit)" "$OWNER_EMAIL_DEFAULT")
  [[ "$OWNER_EMAIL" == "__SKIP__" ]] && OWNER_EMAIL=""
  OWNER_EMAIL=${OWNER_EMAIL:-$OWNER_EMAIL_DEFAULT}

  TELEGRAM_BOT_TOKEN=""
  if prompt_yes_no "Enable Telegram integration?" "N"; then
    TELEGRAM_BOT_TOKEN=$(prompt_secret "Telegram bot token" "")
  fi

  SIGNAL_ACCOUNT=""
  COMPOSE_PROFILES=""
  if prompt_yes_no "Enable Signal integration?" "N"; then
    SIGNAL_ENABLED=true
    COMPOSE_PROFILES="signal"
    SIGNAL_ACCOUNT=$(prompt_text "Signal bot account number" "")
  fi

  if prompt_yes_no "Enable WhatsApp integration?" "N"; then
    WHATSAPP_ENABLED=true
  fi

  WEBHOOK_SECRET=""
  SMTP_HOST=""
  SMTP_PORT=""
  SMTP_USER=""
  SMTP_PASSWORD=""
  FROM_ADDRESS=""
  EMAIL_TRANSPORT_MODE="smtp"

  EMAIL_NONINTERACTIVE=false
  if [[ -n "$EMAIL_MODE_OVERRIDE$EMAIL_WEBHOOK_SECRET_OVERRIDE$EMAIL_OWNER_OVERRIDE$EMAIL_SMTP_HOST_OVERRIDE$EMAIL_SMTP_PORT_OVERRIDE$EMAIL_SMTP_USER_OVERRIDE$EMAIL_SMTP_PASSWORD_OVERRIDE$EMAIL_FROM_OVERRIDE" ]]; then
    EMAIL_NONINTERACTIVE=true
  fi

  if [[ "$EMAIL_NONINTERACTIVE" == true ]]; then
    if [[ -z "$EMAIL_MODE_OVERRIDE" ]]; then
      die "--email-mode is required when using non-interactive --email-* overrides"
    fi
    EMAIL_ENABLED=true
    EMAIL_TRANSPORT_MODE="$EMAIL_MODE_OVERRIDE"
    WEBHOOK_SECRET="$EMAIL_WEBHOOK_SECRET_OVERRIDE"
    [[ -n "$WEBHOOK_SECRET" ]] || die "--email-webhook-secret is required with --email-mode"

    case "$EMAIL_TRANSPORT_MODE" in
      smtp)
        SMTP_HOST="$EMAIL_SMTP_HOST_OVERRIDE"
        SMTP_PORT="$EMAIL_SMTP_PORT_OVERRIDE"
        SMTP_USER="$EMAIL_SMTP_USER_OVERRIDE"
        SMTP_PASSWORD="$EMAIL_SMTP_PASSWORD_OVERRIDE"
        FROM_ADDRESS="$EMAIL_FROM_OVERRIDE"
        [[ -n "$SMTP_HOST" && -n "$SMTP_PORT" && -n "$SMTP_USER" && -n "$SMTP_PASSWORD" && -n "$FROM_ADDRESS" ]] || \
          die "smtp mode requires --email-smtp-host/--email-smtp-port/--email-smtp-user/--email-smtp-password/--email-from"
        ;;
      exedev-relay)
        OWNER_EMAIL="$EMAIL_OWNER_OVERRIDE"
        [[ -n "$OWNER_EMAIL" ]] || die "exedev-relay mode requires --email-owner"
        SMTP_HOST="host.docker.internal"
        SMTP_PORT="2525"
        SMTP_USER="relay"
        SMTP_PASSWORD="relay"
        FROM_ADDRESS="$OWNER_EMAIL"
        info "exe.dev relay outbound enabled (recipient must be exactly: $OWNER_EMAIL)"
        ;;
      inbound-only)
        ;;
      *)
        die "Unhandled email mode: $EMAIL_TRANSPORT_MODE"
        ;;
    esac
  elif prompt_yes_no "Enable email integration?" "N"; then
    EMAIL_ENABLED=true
    WEBHOOK_SECRET=$(prompt_secret "Email webhook secret" "")

    EMAIL_MODE=$(prompt_choice "Email mode:" "SMTP outbound + webhook inbound" "exe.dev relay outbound (owner-email only) + webhook inbound" "Inbound-only (disable outbound send_email)")
    case "$EMAIL_MODE" in
      "SMTP outbound + webhook inbound")
        SMTP_HOST=$(prompt_optional_text "SMTP host (optional; type SKIP to omit)" "")
        [[ "$SMTP_HOST" == "__SKIP__" ]] && SMTP_HOST=""
        SMTP_PORT=$(prompt_optional_text "SMTP port (optional; type SKIP to omit)" "587")
        [[ "$SMTP_PORT" == "__SKIP__" ]] && SMTP_PORT=""
        SMTP_USER=$(prompt_optional_text "SMTP username (optional; type SKIP to omit)" "")
        [[ "$SMTP_USER" == "__SKIP__" ]] && SMTP_USER=""
        SMTP_PASSWORD=$(prompt_secret "SMTP password (optional; press Enter to omit)" "")
        FROM_ADDRESS=$(prompt_optional_text "From address (optional; type SKIP to omit)" "")
        [[ "$FROM_ADDRESS" == "__SKIP__" ]] && FROM_ADDRESS=""
        EMAIL_TRANSPORT_MODE="smtp"
        ;;
      "exe.dev relay outbound (owner-email only) + webhook inbound")
        OWNER_EMAIL_RELAY=$(prompt_text "Owner email (must match your exe.dev account email)" "$OWNER_EMAIL")
        OWNER_EMAIL_RELAY=${OWNER_EMAIL_RELAY:-$OWNER_EMAIL}
        [[ -n "$OWNER_EMAIL_RELAY" ]] || die "exe.dev relay requires owner email"
        OWNER_EMAIL="$OWNER_EMAIL_RELAY"
        SMTP_HOST="host.docker.internal"
        SMTP_PORT="2525"
        SMTP_USER="relay"
        SMTP_PASSWORD="relay"
        FROM_ADDRESS="$OWNER_EMAIL_RELAY"
        EMAIL_TRANSPORT_MODE="exedev-relay"
        info "exe.dev relay outbound enabled (recipient must be exactly: $OWNER_EMAIL_RELAY)"
        ;;
      "Inbound-only (disable outbound send_email)")
        EMAIL_TRANSPORT_MODE="inbound-only"
        ;;
      *)
        die "Unhandled email mode: $EMAIL_MODE"
        ;;
    esac

    info "Inbound email delivery can use either Cloudflare Email Worker or exe.dev receive-email bridge."
  fi

  CODER_MODEL=""
  if prompt_yes_no "Enable coder container?" "N"; then
    CODER_ENABLED=true
    CODER_MODEL=$(prompt_choice "Coder model:" "sonnet" "opus" "haiku")
  fi

  CUSTOM_PROMPT=""
  if prompt_yes_no "Configure custom prompt?" "N"; then
    CUSTOM_PROMPT=$(prompt_multiline "Enter custom prompt")
  fi

  ENV_JSON="$ROOT_DIR/state/render-env.json"
  cat > "$ENV_JSON" <<EOF
{
  "TZ": $(json_quote "$TZ_VALUE"),
  "POSTGRES_USER": $(json_quote "$PG_USER"),
  "POSTGRES_PASSWORD": $(json_quote "$PG_PASSWORD"),
  "POSTGRES_DB": $(json_quote "$PG_DB"),
  "COMPOSE_PROFILES": $(json_quote "$COMPOSE_PROFILES")
}
EOF
  ensure_private_file "$ENV_JSON"
  python3 "$ROOT_DIR/py/render_env.py" < "$ENV_JSON" > "$ENV_PATH"

  TOML_JSON="$ROOT_DIR/state/render-config.json"
  cat > "$TOML_JSON" <<EOF
{
  "provider": $(json_quote "$PROVIDER"),
  "model": $(json_quote "$MODEL"),
  "password": $(json_quote "$PASSWORD"),
  "apiKey": $(json_quote "$API_KEY"),
  "authFile": $(json_quote "$AUTH_FILE"),
  "publicHostname": $(json_quote "$PUBLIC_HOSTNAME"),
  "customPrompt": $(json_quote "$CUSTOM_PROMPT"),
  "owner": {
    "name": $(json_quote "$OWNER_NAME"),
    "signal": $(json_quote "$OWNER_SIGNAL"),
    "telegram": $(json_quote "$OWNER_TELEGRAM"),
    "whatsapp": $(json_quote "$OWNER_WHATSAPP"),
    "email": $(json_quote "$OWNER_EMAIL")
  },
  "coder": {
    "model": $(json_quote "$CODER_MODEL")
  },
  "signal": {
    "account": $(json_quote "$SIGNAL_ACCOUNT")
  },
  "telegram": {
    "botToken": $(json_quote "$TELEGRAM_BOT_TOKEN")
  },
  "email": {
    "webhookSecret": $(json_quote "$WEBHOOK_SECRET"),
    "smtpHost": $(json_quote "$SMTP_HOST"),
    "smtpPort": $(json_quote "$SMTP_PORT"),
    "smtpUser": $(json_quote "$SMTP_USER"),
    "smtpPassword": $(json_quote "$SMTP_PASSWORD"),
    "fromAddress": $(json_quote "$FROM_ADDRESS")
  },
  "whatsapp_enabled": $(python3 -c 'import sys; print("true" if sys.argv[1] == "true" else "false")' "$WHATSAPP_ENABLED")
}
EOF
  ensure_private_file "$TOML_JSON"
  python3 "$ROOT_DIR/py/render_toml.py" < "$TOML_JSON" > "$CONFIG_PATH"
  if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
    strip_seeded_telegram_config_if_disabled "$CONFIG_PATH"
  fi
  load_runtime_metadata
fi

if (( REFRESH_ONLY )) || (( SKIP_CONFIG )); then
  load_runtime_metadata
fi

if [[ "$EMAIL_TRANSPORT_MODE" == "exedev-relay" ]]; then
  if [[ -z "$OWNER_EMAIL" ]]; then
    die "exe.dev relay mode requires [owner].email in config.toml"
  fi
  write_exedev_smtp_relay_override "$STAVROBOT_DIR" "$OWNER_EMAIL" "$ROOT_DIR/scripts/exedev_smtp_relay.py"
else
  remove_exedev_smtp_relay_override "$STAVROBOT_DIR"
fi

if (( CONFIG_ONLY )); then
  SKIP_PLUGINS=1
fi

if (( !SKIP_PLUGINS && !REFRESH_ONLY && !SKIP_CONFIG )); then
  if prompt_yes_no "Review plugin installation choices now?" "N"; then
    prompt_plugin_selection
  fi
fi

AFTER_ENV_HASH=$(sha256_file "$ENV_PATH")
AFTER_CONFIG_HASH=$(sha256_file "$CONFIG_PATH")
ENV_CHANGED=false
CONFIG_CHANGED=false
[[ "$BEFORE_ENV_HASH" != "$AFTER_ENV_HASH" ]] && ENV_CHANGED=true
[[ "$BEFORE_CONFIG_HASH" != "$AFTER_CONFIG_HASH" ]] && CONFIG_CHANGED=true

load_runtime_metadata

if (( CONFIG_ONLY )); then
  info "Config-only mode: wrote config files without rebuilding containers or running plugins"
elif (( REFRESH_ONLY )) || [[ "$BEFORE_HEAD" != "$AFTER_HEAD" ]] || [[ "$ENV_CHANGED" == true ]] || [[ "$CONFIG_CHANGED" == true ]]; then
  info "Rebuilding and recreating stavrobot containers"
  docker_compose_up_recreate "$STAVROBOT_DIR"
  wait_for_stavrobot_ready
else
  info "No rebuild needed"
  if [[ -n "$PASSWORD_FOR_READY" ]]; then
    wait_for_stavrobot_ready
  fi
fi

if (( !SKIP_PLUGINS && !CONFIG_ONLY )); then
  run_plugins_from_state
fi

print_run_summary "$BEFORE_HEAD" "$AFTER_HEAD" "$ENV_CHANGED" "$CONFIG_CHANGED" "$PLUGINS_SELECTED_COUNT" "$PLUGINS_HANDLED" "$PLUGIN_REPORT_FILE"
print_next_steps "$PUBLIC_HOSTNAME_FINAL" "$CODER_ENABLED" "$SIGNAL_ENABLED" "$WHATSAPP_ENABLED" "$EMAIL_ENABLED" "$AUTH_MODE_FINAL" "$EMAIL_TRANSPORT_MODE"
info "See README.md and IMPLEMENTATION_PLAN.md"
