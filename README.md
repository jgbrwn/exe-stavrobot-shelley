# Stavrobot installer

Phase 1 installer project for deploying and updating [stavrobot](https://github.com/skorokithakis/stavrobot) on an exe.dev VM.

## Phase 1 scope

- Pull latest upstream stavrobot first
- Interactively generate `.env` and `data/main/config.toml`
- Support Anthropic directly today
- Offer a first-class OpenRouter provider path in the installer
- Live-fetch current OpenRouter free models as selectable suggestions for that provider path
- Still gather generic OpenAI-compatible details for future/upstream-compatible setups
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
- `shelley-stavrobot-bridge.sh` is the canonical Shelley-facing local bridge and should be the default integration target for any future Shelley rebuild; it now defaults to full JSON output so Shelley/runtime callers can parse response text plus remote IDs without extra flags, while `--extract response` remains available for human-oriented text-only use
- the canonical bridge chat output now also carries the first narrow S2-ready richer fields in a backward-compatible envelope: `content` (markdown-first), compact `display.tool_summary` when available, and `raw` payload retention, while still preserving top-level `response`, `conversation_id`, and `message_id`
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
- any future Shelley-side Stavrobot backend model control should be available only from Stavrobot mode context and should still preserve upstream Shelley behavior unchanged when Stavrobot mode is off
- the likely official Shelley patch seam is above the normal model/provider layer, reusing Shelley's existing working-state UX while waiting on Stavrobot and later evolving the canonical bridge toward richer structured output for markdown/media/tool fidelity
- the likely first Shelley UX for Stavrobot mode should stay compact: explicit mode/profile selection, reused `Agent Working...`, a mode-aware context label, actionable degraded-state recovery, and explicit reset/remap controls
- the current phased roadmap is S1 minimal per-conversation mode, S2 richer structured bridge output, S3 optional history/event reconciliation, and S4 recall validation first before assuming Shelley needs its own cross-conversation retrieval layer
- `docs/SHELLEY_STRATEGIC_GAP_AUDIT.md` now captures the current post-S1 strategic gaps and recommends the near-term order: narrow S2 rich-output scope first, then S4 recall evidence gathering, while preserving upstream Shelley mobile/responsive behavior
- `docs/SHELLEY_S2_STRUCTURED_BRIDGE_TARGET.md` now defines the minimal next structured bridge/adaptation target for Shelley-native markdown/tool-summary/media-reference fidelity while keeping text fallback mandatory
- `docs/SHELLEY_S4_RECALL_VALIDATION_TEMPLATE.md` now turns the recall roadmap into an execution-ready validation template so future sessions can record evidence before deciding whether Shelley needs explicit retrieval orchestration
- `docs/SHELLEY_RUNTIME_ADAPTATION_CONTRACT.md` now defines the preferred runtime-side result/adaptation boundary for managed Shelley patch `0004`, keeping `ResponseText` fallback while preserving room for bridge `content`/`display`/`artifacts`/`raw` widening
- the roadmap now also has explicit validation checklists so future Shelley-side work can be judged phase by phase rather than by architecture discussion alone
- the docs now also include a compact handoff summary so a future session can restart from the current recommendation stack quickly
- a disposable official-Shelley S1 spike has now also validated the core seam: per-conversation Stavrobot mode works above the normal model/provider layer using `conversation_options` plus existing Shelley message/working-state plumbing
- `docs/SHELLEY_S1_SPIKE_EXTRACTION.md` now captures the exact disposable patch shape, the real design signal, and what must change before that shape becomes a managed rebuild target
- `docs/SHELLEY_MANAGED_REBUILD_CONTRACT.md` now captures the installer-owned rebuild state, bridge profile state, refresh logic, and future Shelley-mode flag behavior needed to make that path repeatable
- `docs/SHELLEY_MANAGED_PATCH_REBUILD_RECIPE.md` now captures the concrete official-Shelley checkout/build commands, managed S1 patch ownership, and minimum smoke validation flow needed to make that path operational
- `docs/SHELLEY_MANAGED_PATCH_CLEANUP_PLAN.md` now captures how the captured disposable S1 patch must be cleaned into a maintainable managed patch set, especially around bridge/profile resolution and runtime code boundaries
- `docs/SHELLEY_BRIDGE_PROFILE_RESOLUTION_CONTRACT.md` now defines the narrow installer-managed profile file and lookup behavior the cleaned Shelley patch should depend on instead of hardcoded local bridge/config/base-url assumptions
- the repo now also includes a prototype managed bridge-profile asset and loader at `state/shelley-bridge-profiles.json`, `py/shelley_bridge_profiles.py`, and `manage-shelley-bridge-profiles.sh`
- `patches/shelley/series/` now captures the first repo-owned cleaned managed patch series for the eventual Shelley-side implementation split, and the split `0001` → `0004` prototype patches have now been replay/test validated in order against a fresh upstream Shelley checkout
- `validate-shelley-patch-series.sh` now provides a repo-owned replay/apply + UI-build + Go-test validator for that split Shelley patch series
- the managed `/opt/shelley` rebuild path has now also been revalidated end-to-end in isolated mode: rebuild, isolated serve, normal conversation smoke, Stavrobot first turn, Stavrobot continuation, and persisted mapping verification
- `refresh-shelley-managed-s1.sh` now provides a repo-owned managed refresh helper that reapplies/skips `0001` → `0004`, rebuilds Shelley, optionally runs isolated smoke validation, and writes `state/shelley-mode-build.json`
- `print-shelley-managed-status.sh` now provides a repo-owned read-only status view over managed Shelley rebuild state, bridge-profile state, checkout/binary presence, and whether a rebuild appears required
- `tests/run.sh` now provides a lightweight repo-owned validation driver for helper/status tests under `tests/`, including installer OpenRouter-path coverage, Shelley-mode status JSON/guardrail checks, and bridge-profile helper coverage
- `install-stavrobot.sh` now exposes explicit Shelley-mode entrypoints for the current managed flow via `--print-shelley-mode-status` and `--refresh-shelley-mode`, supports `--print-shelley-mode-status --json` for machine-readable status, and rejects ambiguous mixes with normal installer mutation flags
- `patches/shelley/series/0004-stavrobot-runtime-unit.patch-plan.md` now gives a concrete function-by-function apply scaffold for the focused Shelley runtime-unit extraction
- `patches/shelley/s1-stavrobot-mode-cleaned-runtime-prototype.patch` now captures the first real cleaned-runtime prototype diff from a managed `/opt/shelley` checkout, including the first prototype-hardening pass for a less text-locked `server/stavrobot.go` result shape
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
./install-stavrobot.sh --stavrobot-dir /opt/stavrobot --config-only
./install-stavrobot.sh --stavrobot-dir /opt/stavrobot --skip-config --skip-plugins
```

Current core installer flag semantics:

- `--refresh`
  - pull upstream and rebuild/restart if repo or generated config changed
- `--plugins-only`
  - reuse saved plugin selections against an already-running Stavrobot stack
- `--config-only`
  - write `.env` and `data/main/config.toml` only; skip pull, rebuild, and plugin work
- `--skip-config`
  - reuse existing `.env` and `data/main/config.toml` instead of prompting again
- `--skip-plugins`
  - skip plugin prompting/install/configure steps for this run

## Managed Shelley mode commands

Current installer-facing Shelley mode commands:

```bash
./install-stavrobot.sh --print-shelley-mode-status
./install-stavrobot.sh --print-shelley-mode-status --json
./install-stavrobot.sh --refresh-shelley-mode
./install-stavrobot.sh --refresh-shelley-mode --allow-dirty-shelley
./install-stavrobot.sh --refresh-shelley-mode --skip-shelley-smoke
./install-stavrobot.sh --refresh-shelley-mode --expect-shelley-display-data
```

What they do:

- `--print-shelley-mode-status`
  - read-only human status for managed Shelley mode
- `--print-shelley-mode-status --json`
  - machine-readable status for automation
- `--refresh-shelley-mode`
  - apply/skip the owned Shelley patch series, rebuild Shelley, and run isolated smoke validation
- `--allow-dirty-shelley`
  - allow refresh against an already-modified `/opt/shelley` checkout
- `--skip-shelley-smoke`
  - skip the isolated Shelley smoke pass during refresh
- `--expect-shelley-display-data`
  - require smoke validation to assert persisted `display_data` when sampled Stavrobot turns contain display-hint payloads

Common status interpretation:

- `upstream_status: current`
  - recorded rebuild commit matches the current managed checkout and the checkout is clean
- `upstream_status: current-dirty`
  - recorded rebuild commit matches, but the managed checkout has local modifications
- `recorded_checkout_dirty_at_rebuild: yes`
  - the most recent managed rebuild itself was performed from a dirty checkout
  - human-readable status will also emit a warning block for this case
- `recorded_checkout_dirty_at_rebuild: unknown`
  - status is reading an older rebuild-state file that predates this provenance field
- `profiles_status: current`
  - recorded bridge-profile snapshot still matches current profile state
- `rebuild_required: no`
  - managed Shelley mode currently looks up to date enough for the S1 workflow
- `rebuild_required: yes`
  - refresh is recommended because checkout/binary/profile/build state no longer matches expectations

Guardrails:

- Shelley status/refresh flags are intentionally separate from normal Stavrobot install/config/plugin flows
- ambiguous mixes are rejected by the installer rather than silently choosing precedence

Lightweight helper/status validation:

```bash
./tests/run.sh
./tests/run.sh test-print-shelley-managed-status.sh
./tests/run.sh test-install-stavrobot-openrouter-path.sh
./tests/run.sh test-manage-shelley-bridge-profiles.sh
./tests/run.sh test-manage-stavrobot-model.sh
```

## Operator helper: Stavrobot backend model control

For current operator/admin use, this repo now includes a separate helper for shared Stavrobot backend model inspection and OpenRouter model changes:

```bash
./manage-stavrobot-model.sh get-current --stavrobot-dir /opt/stavrobot
./manage-stavrobot-model.sh list-openrouter-free --stavrobot-dir /opt/stavrobot
./manage-stavrobot-model.sh apply --stavrobot-dir /opt/stavrobot --model openrouter/free
```

Current behavior:

- `get-current`
  - prints machine-readable JSON describing current `provider`, `model`, auth mode, and whether OpenRouter model selection is currently applicable
- `list-openrouter-free`
  - returns live OpenRouter free-model suggestions only when active Stavrobot config is actually using `provider = "openrouter"` with corresponding auth/config
- `apply --model MODEL_ID`
  - edits Stavrobot `config.toml`, restarts the `app` service, falls back to force-recreate if needed, and waits for health to report the expected provider/model

Important scope notes:

- this is an explicit operator helper, not part of the normal installer flow
- this mutates the shared local Stavrobot backend model, not per-conversation Shelley metadata
- Shelley-native UI exposure for this should remain a later Stavrobot-mode-only admin surface layered on top of this helper boundary

## Status

Phase 1 is implemented and usable. Phase 2 has started with the Cloudflare automation track.

## Current implementation status

Implemented so far:

- Upstream Stavrobot repo validation and `git pull --ff-only`
- First-class OpenRouter provider prompting in the installer
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
- `--config-only` is a write-only config path and intentionally skips pull/rebuild/plugin actions.
- `--skip-config` reuses the current `.env` and `data/main/config.toml`; pair it with `--skip-plugins` when you want a mostly no-op validation pass.
- The installer now has a first-class OpenRouter provider path with live free-model selection, but current upstream Stavrobot config still lacks an explicit arbitrary base-URL field for broader arbitrary OpenAI-compatible endpoint setup.
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
