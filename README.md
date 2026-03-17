# Stavrobot installer

Phase 1 installer project for deploying and updating [stavrobot](https://github.com/skorokithakis/stavrobot) on an exe.dev VM.

## Phase 1 scope

- Pull latest upstream stavrobot first
- Interactively generate `.env` and `data/main/config.toml`
- Support Anthropic directly today
- Surface OpenRouter free-model suggestions and gather generic OpenAI-compatible details for future/upstream-compatible setups
- Live-fetch current OpenRouter free models as suggestions
- Start/rebuild Stavrobot with Docker Compose
- Collect plugin config values up front, then install/configure plugins against the running app
- Print clear post-install next steps for manual integrations

## Not in Phase 1

- Shelley custom rebuilds
- Shelley "Stavrobot mode"
- Stavrobot code changes

## Phase 2 in progress

Two Phase 2 tracks have now started:

### Cloudflare automation

- `install-cloudflare-email-worker.sh` generates a deployable Cloudflare Email Worker bundle from existing Stavrobot config
- output includes `worker.js`, `wrangler.toml`, `.dev.vars.example`, worker-specific `README.md`, and deployment `CHECKLIST.md`
- optional `--deploy` support can run Wrangler deploy and upload `WEBHOOK_SECRET`

Still manual in this track:

- Cloudflare account auth/login if not already set up
- Cloudflare Email Routing rule creation in the dashboard

### Shelley integration MVP

- `chat-with-stavrobot.sh` is a thin adapter around Stavrobot's authenticated `POST /chat` endpoint
- `shelley-stavrobot-bridge.sh` is the canonical Shelley-facing local bridge and should be the default integration target for any future Shelley rebuild
- `client-stavrobot.sh` is a lower-level machine-oriented wrapper around the validated authenticated `/api/client/*` surface
- `shelley-stavrobot-session.sh` is a lower-level stateful convenience wrapper that persists and reuses the last `conversation_id`
- `smoke-test-stavrobot-client.sh` validates the local client surface against the running stack
- the intended future rebuild shape remains an optional Shelley "Stavrobot mode"; if that mode is not enabled, Shelley should continue behaving as before
- the eventual installer follow-up should gain an explicit optional Shelley-aware rebuild/update path rather than making Shelley mode part of every normal install
- the actual optional Shelley "Stavrobot mode" likely belongs in the official Shelley repo itself, while this repo later orchestrates fetching from upstream, rebuilding locally, and recording the upstream Shelley hash used for that rebuild when requested
- the currently preferred future Shelley shape is per-conversation mode using conversation-scoped metadata such as a Stavrobot `conversation_id`, optional last `message_id`, and an installer-managed local bridge profile name
- installer-managed Shelley rebuilds should later track upstream Shelley commit/hash plus local bridge-profile state separately from per-conversation metadata
- the likely future installer CLI should keep Shelley work explicit via opt-in/status/refresh flags rather than changing normal installs silently
- the likely future Shelley-side implementation should treat Stavrobot mode as a small per-conversation lifecycle/state machine rather than only a boolean toggle
- the likely official Shelley patch seam is above the normal model/provider layer, reusing Shelley's existing working-state UX while waiting on Stavrobot and later evolving the canonical bridge toward richer structured output for markdown/media/tool fidelity
- the likely first Shelley UX for Stavrobot mode should stay compact: explicit mode/profile selection, reused `Agent Working...`, a mode-aware context label, actionable degraded-state recovery, and explicit reset/remap controls
- the current phased roadmap is S1 minimal per-conversation mode, S2 richer structured bridge output, S3 optional history/event reconciliation, and S4 recall validation first before assuming Shelley needs its own cross-conversation retrieval layer
- the roadmap now also has explicit validation checklists so future Shelley-side work can be judged phase by phase rather than by architecture discussion alone
- the docs now also include a compact handoff summary so a future session can restart from the current recommendation stack quickly
- a disposable official-Shelley S1 spike has now also validated the core seam: per-conversation Stavrobot mode works above the normal model/provider layer using `conversation_options` plus existing Shelley message/working-state plumbing
- long-lived Shelley conversations should remain viable if Stavrobot mode is implemented as frontend-to-Stavrobot continuation rather than replaying an ever-growing Shelley transcript through a normal model-provider path each turn
- `docs/SHELLEY_STAVROBOT_MVP.md` records the recommended MVP and likely next upstream API asks
- separate upstream spike work validated additive `GET /api/client/health`, `POST /api/client/chat`, `GET /api/client/conversations`, `GET /api/client/conversations/:conversation_id/messages`, and `GET /api/client/conversations/:conversation_id/events`
- the client chat spike produced a real successful LLM-backed response with OpenRouter using model `z-ai/glm-4.5-air:free`
- the upstream spike now also returns real `conversation_id` values, real chat `message_id` values, and exposes conversation listing/history/events
- live runtime passes against the rebuilt stack also validated health, first chat, conversation listing, message history, second-turn continuation on the same `conversation_id`, machine-readable tool-call/tool-result events, and a chat `message_id` that matched persisted history

## Intended layout

```text
/opt/stavrobot/                 # upstream clone
/opt/stavrobot-installer/       # this repo
```

## Planned usage

```bash
./install-stavrobot.sh --stavrobot-dir /opt/stavrobot
./install-stavrobot.sh --stavrobot-dir /opt/stavrobot --refresh
./install-stavrobot.sh --stavrobot-dir /opt/stavrobot --plugins-only
```

## Status

Phase 1 is implemented and usable. Phase 2 has started with the Cloudflare automation track.

## Current implementation status

Implemented so far:

- Upstream Stavrobot repo validation and `git pull --ff-only`
- OpenRouter free-model fetch and local caching
- Interactive core config prompts
- Clean generation of `.env` and `data/main/config.toml`
- Docker Compose rebuild/recreate on change
- Basic authenticated readiness check against Stavrobot
- Interactive plugin selection
- Required and optional plugin config prompts
- Saved plugin selections in `state/last-plugin-inputs.json`
- Install and configure selected plugins against the running Stavrobot instance after startup
- Phase 2 starter: Cloudflare email worker bundle generation
- Phase 2 starter: Shelley-to-Stavrobot chat adapter script

## Plugin state

Selected plugin installs are saved to:

- `state/last-plugin-inputs.json`

This file may contain plugin secrets. It is written with mode `0600`.

## Current caveats

- `--plugins-only` reuses `state/last-plugin-inputs.json` if present.
- Generic OpenAI-compatible provider prompting is present, but current upstream Stavrobot config still lacks an explicit arbitrary base-URL field.
- Cloudflare email worker automation currently generates/deploys the worker bundle, but Email Routing rule creation is still manual.
- Non-interactive automation is not finished yet.

## Manual integrations still left to the operator

The installer can generate config for these, but some final activation steps are still manual:

- `authFile` login flow
- Signal registration/linking
- WhatsApp QR linking
- Cloudflare Email Routing rule creation
- Claude Code login for the coder container

## Plugin run report

The most recent plugin install/configure results are written to:

- `state/last-plugin-report.txt`

## Cloudflare email worker automation

Generate a worker bundle from existing Stavrobot config:

```bash
./install-cloudflare-email-worker.sh --stavrobot-dir /opt/stavrobot
```

Override values or deploy directly:

```bash
./install-cloudflare-email-worker.sh \
  --stavrobot-dir /opt/stavrobot \
  --worker-name stavrobot-email-worker \
  --account-id YOUR_CF_ACCOUNT_ID \
  --deploy
```

This reads `publicHostname` and `email.webhookSecret` from `data/main/config.toml` when available.

Generated bundle location by default:

- `state/cloudflare-email-worker/`

Contents:

- `worker.js`
- `wrangler.toml`
- `.dev.vars.example`
- `README.md`
- `CHECKLIST.md`

## Shelley integration MVP

Send a message to a running Stavrobot instance through the adapter:

```bash
./chat-with-stavrobot.sh \
  --stavrobot-dir /opt/stavrobot \
  --message "Hello from Shelley"
```

Or pipe stdin:

```bash
printf 'Summarize the last deployment status' | ./chat-with-stavrobot.sh --stavrobot-dir /opt/stavrobot
```

By default the script prints only Stavrobot's `response` field. Use `--raw-json` to inspect the full API response.

Useful adapter flags:

- `--connect-timeout`
- `--request-timeout`
- `--retries`
- `--retry-delay`

Canonical Shelley-facing bridge examples:

```bash
./shelley-stavrobot-bridge.sh --stavrobot-dir /opt/stavrobot --message "Summarize current status"
./shelley-stavrobot-bridge.sh --stavrobot-dir /opt/stavrobot --message "Summarize current status" --extract conversation_id
./shelley-stavrobot-bridge.sh --stavrobot-dir /opt/stavrobot show-session
./shelley-stavrobot-bridge.sh --stavrobot-dir /opt/stavrobot messages --pretty
./shelley-stavrobot-bridge.sh --stavrobot-dir /opt/stavrobot events --pretty
./shelley-stavrobot-bridge.sh --stavrobot-dir /opt/stavrobot reset-session
```

Lower-level machine-oriented client wrapper examples:

```bash
./client-stavrobot.sh --stavrobot-dir /opt/stavrobot health --pretty
./client-stavrobot.sh --stavrobot-dir /opt/stavrobot conversations --pretty
./client-stavrobot.sh --stavrobot-dir /opt/stavrobot chat --message "Summarize current status" --pretty
./client-stavrobot.sh --stavrobot-dir /opt/stavrobot chat --message "Summarize current status" --extract response
./client-stavrobot.sh --stavrobot-dir /opt/stavrobot chat --message "Summarize current status" --extract conversation_id
./client-stavrobot.sh --stavrobot-dir /opt/stavrobot messages --conversation-id conv_1 --pretty
./client-stavrobot.sh --stavrobot-dir /opt/stavrobot events --conversation-id conv_1 --pretty
```

Lower-level stateful session wrapper examples:

```bash
./shelley-stavrobot-session.sh --stavrobot-dir /opt/stavrobot chat --message "First turn" --pretty
./shelley-stavrobot-session.sh --stavrobot-dir /opt/stavrobot continue --message "Second turn" --pretty
./shelley-stavrobot-session.sh --stavrobot-dir /opt/stavrobot continue --message "Second turn" --extract response
./shelley-stavrobot-session.sh get --extract conversation_id
./shelley-stavrobot-session.sh get --extract message_id
./shelley-stavrobot-session.sh --stavrobot-dir /opt/stavrobot show
./shelley-stavrobot-session.sh --stavrobot-dir /opt/stavrobot messages --pretty
./shelley-stavrobot-session.sh --stavrobot-dir /opt/stavrobot events --pretty
./shelley-stavrobot-session.sh reset
```

Design notes live in:

- `docs/SHELLEY_STAVROBOT_MVP.md`

Additional API notes for Shelley follow-up:

- `docs/STAVROBOT_API_NOTES.md`

Upstream API proposal for better Shelley support:

- `docs/STAVROBOT_UPSTREAM_API_PROPOSAL.md`

## Shelley adapter smoke tests

Quick validation harnesses:

```bash
./smoke-test-stavrobot-adapter.sh --stavrobot-dir /opt/stavrobot
./smoke-test-stavrobot-client.sh --stavrobot-dir /opt/stavrobot
```

Default local base URL is now `http://localhost:8000`. Override with `--base-url` or `STAVROBOT_BASE_URL` when needed.

Docs:

- `docs/SHELLEY_ADAPTER_SMOKE_TESTS.md`
