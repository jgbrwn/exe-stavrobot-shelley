# Implementation plan

## Goal

Build a standalone, Bash-first installer for Stavrobot on exe.dev VMs. The installer must be deterministic, idempotent where practical, and must not depend on Stavrobot's LLM to complete setup.

## Core decisions

1. Keep this installer in a separate repo from the upstream Stavrobot clone.
2. Use Bash for orchestration and Python for structured parsing/rendering.
3. Generate clean `.env` and `data/main/config.toml` files rather than patching example files in place.
4. Live-fetch OpenRouter free models from `https://openrouter.ai/api/v1/models` and present them as optional suggestions.
5. Always allow manual provider, base URL, and model entry for any OpenAI-compatible setup.
6. Collect plugin configuration values during prompting, then install and configure plugins after Stavrobot is running.
7. Use Stavrobot's authenticated HTTP plugin-management endpoints instead of asking the LLM to install plugins.
8. Rebuild with `docker compose up -d --build --force-recreate` whenever repo HEAD or generated config changes.
9. Leave Cloudflare worker automation and Shelley integration for Phase 2.

## Repo structure

```text
install-stavrobot.sh
lib/
  common.sh
  prompts.sh
  repo.sh
  docker.sh
  stavrobot_api.sh
  summary.sh
py/
  openrouter_models.py
  load_current_config.py
  render_env.py
  render_toml.py
  catalog_normalize.py
data/
  core-schema.json
  plugin-catalog.json
state/
  .gitkeep
```

## Exact Phase 1 flow

1. Validate prerequisites.
2. Validate Stavrobot repo path.
3. Refuse to pull if the upstream repo has dirty tracked changes.
4. `git pull --ff-only` the upstream repo.
5. Load defaults from `env.example` and `config.example.toml` plus current values from `.env` and `data/main/config.toml`.
6. Prompt for required settings first.
7. Prompt for optional settings and integrations.
8. Prompt for plugin selection and collect plugin config values.
9. Render `.env` and `data/main/config.toml`.
10. Detect whether repo HEAD or config changed.
11. Run `docker compose up -d --build --force-recreate` if needed.
12. Wait for Stavrobot readiness using authenticated HTTP checks.
13. Install and configure selected plugins through Stavrobot's HTTP API.
14. Print final URLs and manual next steps.

## Provider UX

### Anthropic

Prompt for:
- provider = `anthropic`
- model
- auth mode: `apiKey` or `authFile`

### OpenAI-compatible

Prompt for:
- provider label
- base URL
- model ID
- API key

Before prompting, try to fetch current OpenRouter free models and show them as suggestions alongside the OpenRouter v1 endpoint URL.

## Prompt semantics

- Blank input keeps current value if present, otherwise default.
- `SKIP` unsets an optional value.
- Secrets are masked by default.
- `--show-secrets` disables masking.

## Plugin handling

The installer should maintain a curated catalog of first-party Stavrobot plugins. For each selected plugin:

1. Prompt for required config values.
2. Prompt for optional config values.
3. Save selections in `state/last-plugin-inputs.json` with mode `0600`.
4. After startup, call Stavrobot to install the plugin.
5. Then call Stavrobot to configure the plugin.
6. Verify the plugin appears in the installed plugin list.

## Error policy

Hard fail on:
- invalid repo path
- dirty upstream repo before pull
- pull failure
- config render failure
- Docker Compose failure
- readiness failure
- selected plugin install/config failure

Soft warn on:
- OpenRouter fetch failure
- plugin already installed
- optional plugin skipped
- manual integrations not automated in Phase 1

## Phase 2

Tracks:
- Cloudflare email worker automation
- Shelley "Stavrobot mode"
- Optional Stavrobot history/events API work to support Shelley as a better frontend
- Shelley rebuild automation

Current Phase 2 starting points:
- Generate a Cloudflare Email Worker bundle from current Stavrobot config
- Optionally deploy it with Wrangler when available
- Keep Cloudflare Email Routing rule creation manual for now
- Start Shelley integration with a thin adapter over existing Stavrobot `/chat` behavior

Important scope constraint for Shelley work:
- "Shelley Stavrobot mode" should be optional.
- When that mode is not enabled, Shelley should continue to behave as it did originally.
- The Shelley rebuild should target one canonical local bridge rather than depending directly on every helper script.
- The eventual installer flow must know how to enable/refresh that optional Shelley mode without forcing it on every install.

## Discovered upstream limitation

While implementing Phase 1, we verified that current upstream Stavrobot exposes `provider`, `model`, `apiKey`, and `authFile` in `config.toml`, but no explicit base-URL field for arbitrary OpenAI-compatible endpoints. The installer can still present OpenRouter free-model suggestions and collect generic provider details, but full arbitrary OpenAI-compatible endpoint setup may require upstream Stavrobot changes in Phase 2.

## Implemented increment

The installer now supports Phase 1 core config generation plus a first pass at plugin prompting and plugin installation/configuration through Stavrobot's authenticated HTTP endpoints.

## Hardening updates

The installer now supports `--plugins-only`, reusing saved plugin state from `state/last-plugin-inputs.json`. Prompt handling for optional owner fields was also tightened so skipped values are omitted from generated config output.

## Final Phase 1 polish

The installer now prints richer next-step guidance, tracks per-plugin outcomes in `state/last-plugin-report.txt`, supports email config prompting, and suppresses empty plugin-result sections in the final summary.

## Phase 2 increment: Cloudflare automation track

Implemented starter scope:

1. Add `install-cloudflare-email-worker.sh` as a separate Phase 2 entrypoint.
2. Read `publicHostname` and `email.webhookSecret` from Stavrobot config when available.
3. Render a ready-to-review Cloudflare worker bundle containing:
   - `worker.js`
   - `wrangler.toml`
   - `.dev.vars.example`
   - worker-specific `README.md`
   - deployment-specific `CHECKLIST.md`
4. Support optional `--deploy` flow using Wrangler plus `wrangler secret put WEBHOOK_SECRET`.
5. Print domain-aware next steps and validation hints.
6. Leave dashboard Email Routing rule creation manual until a later increment.

Rationale:
- This captures the repetitive, error-prone parts first.
- It does not require undocumented Cloudflare APIs.
- It keeps the first Phase 2 increment testable without broadening scope into Shelley integration yet.

## Phase 2 increment: Shelley integration MVP

Implemented starter scope:

1. Add `chat-with-stavrobot.sh` as a local adapter entrypoint.
2. Read Stavrobot Basic Auth password from `data/main/config.toml` when available.
3. Post prompts to authenticated `POST /chat`.
4. Print the assistant `response` by default, with `--raw-json` available for debugging.
5. Document the MVP and likely future upstream API requests in `docs/SHELLEY_STAVROBOT_MVP.md`.

Rationale:
- This gives Shelley an immediate, low-risk integration surface.
- It avoids blocking on upstream conversation/history/event APIs.
- It keeps the first Shelley increment concrete and testable.

## Shelley follow-up notes

After the adapter MVP, prefer validating real Shelley workflows against existing `/chat` behavior before proposing Stavrobot API changes. Track current API observations and likely future asks in `docs/STAVROBOT_API_NOTES.md`.

## Shelley upstream API proposal

A first additive proposal for machine-oriented Stavrobot endpoints now lives in `docs/STAVROBOT_UPSTREAM_API_PROPOSAL.md`. The proposal intentionally preserves current `/chat` behavior and introduces a separate `/api/client/*` namespace for Shelley and similar clients.

## Shelley adapter validation

A small local harness exists in `smoke-test-stavrobot-adapter.sh` to validate the current adapter path and common failure modes.

## Shelley client validation

The main repo now includes several Shelley-side local layers:

- `client-stavrobot.sh` as the lower-level wrapper around the validated `/api/client/*` surface
- `shelley-stavrobot-session.sh` as a tiny stateful conversation helper
- `shelley-stavrobot-bridge.sh` as the canonical Shelley-facing bridge for future rebuild work
- `smoke-test-stavrobot-client.sh` to exercise health, chat, conversation listing, history, and events against a live stack

This means the next Shelley rebuild step should wire only the canonical bridge into the optional Shelley Stavrobot mode, while leaving the lower-level helper scripts as implementation details and operator/debug tools.

## Planned Shelley rebuild + installer wiring

The repo does not yet contain the actual Shelley source tree or rebuild pipeline. So the current work establishes the local integration contract first.

When Shelley rebuild automation is added, the intended shape should be:

1. Installer remains primarily a Stavrobot installer.
2. Shelley integration remains optional and explicit.
3. Installer gains a Phase 2 Shelley-aware path such as:
   - disabled by default
   - optional `--with-shelley-stavrobot-mode`
   - optional `--refresh-shelley-mode`
4. That Shelley-aware path should:
   - locate or update the Shelley source/rebuild target from upstream
   - record the upstream Shelley commit/hash used for the local rebuild
   - configure Shelley to expose an optional "Stavrobot mode"
   - wire that mode to invoke only `shelley-stavrobot-bridge.sh`
   - leave normal Shelley behavior unchanged when the mode is not enabled
5. The installer should not need to know the lower-level wrapper details beyond ensuring the canonical bridge is present and usable.

Practical consequence:
- the shell wrappers created in this repo are preparing the contract for the future Shelley rebuild
- the eventual installer wiring should enable or refresh that mode against the canonical bridge rather than reproduce the integration logic itself
- the installer should be able to compare the stored upstream Shelley hash with upstream HEAD to decide whether a Shelley-mode rebuild is already current

What is still missing before that implementation step:
- the exact local checkout/build location this repo should manage for Shelley
- the concrete artifact/state file format for storing the upstream Shelley hash used for a rebuild
- the exact config toggle or runtime flag that will represent optional "Stavrobot mode"

## Shelley mode implementation recommendation

Based on disposable inspection of the official Shelley repo, the likely clean implementation seam is above Shelley's model/provider layer.

Recommendation:

- do not model Stavrobot as just another LLM provider inside Shelley
- instead add an optional higher-level Shelley runtime/conversation mode that delegates turns to `shelley-stavrobot-bridge.sh`
- then map Stavrobot responses, conversation IDs, history, events, and future rich artifacts into Shelley's own conversation/message/display model

Why this is the cleaner fit:

- Shelley's model layer is oriented around direct LLM services
- Stavrobot is an agent service with its own conversation and event semantics
- Shelley already has richer UI/message/media/display capabilities than a plain model transport abstraction captures well

This recommendation should guide both the future Shelley spike work and the eventual installer-assisted rebuild path.
