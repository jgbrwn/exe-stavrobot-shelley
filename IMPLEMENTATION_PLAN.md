# Implementation plan

## Goal

Build a standalone, Bash-first installer for Stavrobot on exe.dev VMs. The installer must be deterministic, idempotent where practical, and must not depend on Stavrobot's LLM to complete setup.

## Core decisions

1. Keep this installer in a separate repo from the upstream Stavrobot clone.
2. Use Bash for orchestration and Python for structured parsing/rendering.
3. Generate clean `.env` and `data/main/config.toml` files rather than patching example files in place.
4. Live-fetch OpenRouter free models from `https://openrouter.ai/api/v1/models` and present them in a first-class OpenRouter provider flow.
5. Still allow manual provider and model entry for broader OpenAI-compatible setups, noting that upstream Stavrobot currently lacks an explicit arbitrary base-URL field.
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

### OpenRouter

Prompt for:
- provider = `openrouter`
- auth mode: `apiKey` or `authFile`
- model from live OpenRouter free-model choices when available
- manual model entry fallback

Include `openrouter/free` in the selectable list.

### OpenAI-compatible

Prompt for:
- provider label
- model ID
- API key

This path remains generic/manual because current upstream Stavrobot config still lacks an explicit arbitrary base-URL field.

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

While implementing Phase 1, we verified that current upstream Stavrobot exposes `provider`, `model`, `apiKey`, and `authFile` in `config.toml`, but no explicit base-URL field for arbitrary OpenAI-compatible endpoints. The installer should therefore treat OpenRouter as a first-class provider path with live free-model selection, while broader arbitrary OpenAI-compatible endpoint setup may still require upstream Stavrobot changes in Phase 2.

## Implemented increment

The installer now supports Phase 1 core config generation plus a first pass at plugin prompting and plugin installation/configuration through Stavrobot's authenticated HTTP endpoints.

## Hardening updates

The installer now supports `--plugins-only`, reusing saved plugin state from `state/last-plugin-inputs.json`. It also now honors `--config-only` and `--skip-config` explicitly rather than leaving them as stale flag surface. Prompt handling for optional owner fields was also tightened so skipped values are omitted from generated config output.

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

## Minimal per-conversation Shelley metadata recommendation

For the likely per-conversation Shelley implementation, the first rebuild should keep the stored metadata small and explicit.

Recommended minimum conversation-scoped shape:

- `mode = "stavrobot"`
- `stavrobot.enabled = true`
- `stavrobot.conversation_id = "conv_<id>"`
- `stavrobot.last_message_id = "msg_<id>"` when known
- `stavrobot.bridge_profile = "local-default"`

Rationale:

- `mode` or equivalent conversation option enables the alternate runtime path cleanly
- `conversation_id` is the durable mapping needed for normal continuation
- `last_message_id` is useful as a sync/checkpoint hint without becoming mandatory for every turn
- `bridge_profile` lets Shelley refer to an installer-managed local integration profile without embedding secrets or raw auth details inside conversation metadata

Important limits for the first version:

- keep secrets out of conversation metadata
- do not require raw per-conversation base URLs if one installer-managed local bridge profile is enough
- treat cross-conversation recall as separate from the active conversation mapping
- continue treating `shelley-stavrobot-bridge.sh` as the only supported local contract

## Long-running conversation and context-window recommendation

A single Shelley conversation could reasonably remain mapped to one Stavrobot conversation for a very long time.

That does not necessarily make Shelley slow if Stavrobot mode is implemented correctly.

Key distinction:

- in ordinary Shelley direct-model mode, a context indicator may reflect Shelley/provider prompt pressure
- in Shelley Stavrobot mode, the active durable context should primarily live in Stavrobot, not in a repeatedly replayed Shelley-side transcript

So the recommended behavior is:

1. do not assume Shelley's ordinary direct-model context gauge is the authoritative measure in Stavrobot mode
2. avoid implementing Stavrobot mode in a way that resends the full Shelley transcript through a normal model-provider path every turn
3. prefer a mode-specific UI state such as "context managed by Stavrobot" unless or until Stavrobot exposes a meaningful context/window metric
4. if Stavrobot later exposes a real estimate, Shelley can render a separate mode-aware gauge rather than a misleading direct-model one

Operationally, this reinforces the higher-level runtime-mode design:

- Shelley is the frontend and renderer
- Stavrobot owns the active conversation state
- long-lived conversation viability depends more on Stavrobot's own context/retrieval strategy than on the mere age or length of the Shelley conversation object

## Installer-managed rebuild mapping

The later installer-managed Shelley rebuild path should map to that metadata shape conservatively.

Recommended installer responsibilities:

1. fetch or refresh a local Shelley checkout from upstream
2. record the upstream Shelley commit/hash used for the custom rebuild
3. build a Shelley variant that understands the per-conversation `mode = "stavrobot"` metadata shape
4. ensure that Stavrobot-mode conversations invoke only `shelley-stavrobot-bridge.sh`
5. install or refresh one or more local bridge profiles outside conversation metadata
6. leave normal Shelley conversations untouched when the mode is not enabled

Recommended installer-managed local state shape later:

- a rebuild status file recording at least:
  - upstream Shelley repo URL
  - upstream Shelley commit/hash built
  - local rebuild timestamp
  - local bridge script path
  - available bridge profile names

That separation is important:

- conversation metadata answers "should this conversation use Stavrobot and which remote conversation is it mapped to?"
- installer-managed rebuild state answers "which Shelley source was rebuilt locally and which local bridge profile(s) exist?"

This keeps per-conversation mode lightweight while still giving the installer enough information to detect stale Shelley rebuilds and refresh them deliberately.

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

## Per-conversation mode and memory recommendation

Official Shelley's existing conversation architecture suggests that optional Stavrobot mode should likely be stored per conversation rather than only as a server-wide switch.

Recommendation:

- use per-conversation mode as the target design
- allow a simpler broader-scope spike only if it meaningfully reduces initial validation cost
- keep in mind that active-thread continuity and global historical recall are different capabilities

Implication for memory:

- mapping one Shelley conversation to one Stavrobot conversation handles active continuity well
- broader "remember when we did X weeks ago" behavior likely requires an additional retrieval layer over Stavrobot conversation listing/history
- the currently validated Stavrobot API surface is sufficient for basic explicit retrieval workflows, but not yet for dedicated semantic/global memory search


## Draft installer-managed Shelley rebuild state

To support optional Shelley rebuilds without overloading conversation metadata, the installer should eventually own a separate local state file for Shelley-mode rebuild tracking.

A practical first file could be something like:

- `state/shelley-mode-build.json`

Recommended draft shape:

```json
{
  "schema_version": 1,
  "managed_by": "exe-stavrobot-shelley",
  "shelley": {
    "repo_url": "https://github.com/boldsoftware/shelley",
    "branch": "main",
    "upstream_commit": "5b072309d8a086b6a4fe8a550b473c5805d73ae5",
    "checkout_path": "/opt/shelley",
    "binary_path": "/opt/shelley/bin/shelley",
    "rebuilt_at": "2025-01-01T12:34:56Z"
  },
  "stavrobot_mode": {
    "enabled_in_build": true,
    "bridge_script": "/opt/stavrobot-installer/shelley-stavrobot-bridge.sh",
    "profiles": {
      "local-default": {
        "base_url": "http://localhost:8000",
        "config_path": "/opt/stavrobot/data/main/config.toml"
      }
    }
  }
}
```

Why this file should exist separately from Shelley conversation data:

- it records rebuild provenance and staleness information
- it records installer-managed local bridge profile definitions
- it avoids putting machine-local filesystem paths and auth-related config locations into per-conversation metadata
- it lets many Shelley conversations reference one shared local bridge profile cleanly

Recommended minimum fields:

- `schema_version`
- `managed_by`
- `shelley.repo_url`
- `shelley.branch`
- `shelley.upstream_commit`
- `shelley.checkout_path`
- `shelley.binary_path`
- `shelley.rebuilt_at`
- `stavrobot_mode.enabled_in_build`
- `stavrobot_mode.bridge_script`
- `stavrobot_mode.profiles`

Recommended staleness logic later:

1. installer fetches remote Shelley upstream HEAD for the tracked branch
2. compare remote HEAD to `shelley.upstream_commit`
3. if equal, the local Shelley-mode rebuild is probably current from an upstream-source perspective
4. if different, offer or perform `--refresh-shelley-mode`
5. if the bridge path or selected profile definitions changed materially, treat that as a local rebuild/profile refresh trigger too

Recommended profile semantics:

- conversation metadata stores only a profile name such as `local-default`
- installer-managed rebuild state resolves that profile name into machine-local config such as:
  - base URL
  - config path or stavrobot dir
  - optional timeout defaults later
- secrets should still preferably live in the Stavrobot config itself, not duplicated into this state file unless absolutely necessary

Recommended future extension fields if needed:

- `shelley.local_patch_commit`
- `shelley.build_command`
- `shelley.service_name`
- `stavrobot_mode.default_profile`
- `stavrobot_mode.profile_env`
- `stavrobot_mode.bridge_version`

But the minimal file should stay focused on provenance, bridge path, and profile mapping.

## Recommended mapping between Shelley conversation metadata and installer-managed state

The intended separation of concerns should be:

### Shelley conversation metadata

Stores only what is needed to drive one conversation:

- whether this conversation is in Stavrobot mode
- which remote Stavrobot conversation it is mapped to
- which installer-managed local profile name to use
- optionally the last known remote message ID

### Installer-managed Shelley rebuild state

Stores machine-local and rebuild-local facts:

- which Shelley upstream commit was rebuilt
- where the local Shelley checkout and binary live
- whether Stavrobot mode support is present in that build
- where the canonical bridge script lives
- which local bridge profiles exist

That gives a clean model:

- many Shelley conversations can share one installer-managed bridge profile
- refreshing the Shelley rebuild does not require rewriting all conversations
- switching one conversation in or out of Stavrobot mode does not require changing installer state
- upstream hash tracking remains local and operational rather than leaking into user conversation data


## Draft installer CLI contract for optional Shelley mode

When Shelley rebuild automation is eventually added, the installer should expose a small explicit CLI surface rather than silently changing normal installs.

Recommended flags:

### Primary mode flags

- `--with-shelley-stavrobot-mode`
  - fetch/build/refresh Shelley with optional Stavrobot-mode support enabled
- `--refresh-shelley-mode`
  - force a Shelley-mode refresh check and rebuild flow even if normal Stavrobot install/update work would not touch Shelley
- `--print-shelley-mode-status`
  - print current local Shelley-mode rebuild/profile state and whether it appears stale relative to upstream

### Shelley source/build location flags

- `--shelley-dir PATH`
  - local Shelley checkout/build directory to manage
- `--shelley-branch BRANCH`
  - Shelley upstream branch to track, default likely `main`
- `--shelley-repo-url URL`
  - optional override for Shelley upstream repo URL

### Bridge profile flags

- `--shelley-profile-name NAME`
  - installer-managed profile name to create or refresh, default likely `local-default`
- `--shelley-base-url URL`
  - base URL that the profile should use for Stavrobot, default likely `http://localhost:8000`
- `--shelley-config-path PATH`
  - explicit Stavrobot `config.toml` path for that profile
- `--shelley-stavrobot-dir PATH`
  - alternate convenience input from which the installer can derive `config.toml`

### Behavior/policy flags

- `--skip-shelley-upstream-check`
  - use existing local Shelley checkout/build metadata without checking remote upstream freshness
- `--force-shelley-rebuild`
  - rebuild even if recorded upstream hash and local profile state look current
- `--disable-shelley-mode`
  - disable future installer-managed Shelley-mode refreshes and record that the local build should no longer be treated as an active managed Shelley-mode target

Recommended behavior summary:

- default installer runs should not touch Shelley
- `--with-shelley-stavrobot-mode` opt-in should be explicit
- `--print-shelley-mode-status` should be safe and read-only
- `--refresh-shelley-mode` should use the stored rebuild state if present and fail clearly if required Shelley-mode metadata is missing
- `--force-shelley-rebuild` should bypass staleness heuristics but still record fresh rebuild metadata afterward

## Recommended command semantics

### 1. First-time enable flow

Example:

```bash
./install-stavrobot.sh \
  --stavrobot-dir /opt/stavrobot \
  --with-shelley-stavrobot-mode \
  --shelley-dir /opt/shelley \
  --shelley-profile-name local-default
```

Recommended effect:

1. run normal Stavrobot install/update flow
2. fetch or update Shelley checkout in `/opt/shelley`
3. determine upstream Shelley HEAD for the selected branch
4. apply/build the optional Shelley-side Stavrobot-mode variant
5. verify the canonical bridge path exists and is executable
6. create or refresh installer-managed profile `local-default`
7. write `state/shelley-mode-build.json`
8. print resulting Shelley upstream hash, local profile name, and next-step guidance

### 2. Refresh flow

Example:

```bash
./install-stavrobot.sh --refresh-shelley-mode
```

Recommended effect:

1. load `state/shelley-mode-build.json`
2. check whether the tracked Shelley upstream branch has advanced
3. check whether bridge path/profile inputs changed materially
4. rebuild if stale or requested
5. rewrite state file with fresh timestamp/hash/profile state
6. leave ordinary non-Stavrobot Shelley conversations untouched

If no prior Shelley-mode state exists, this command should fail with a clear message instructing the operator to run `--with-shelley-stavrobot-mode` first.

### 3. Status flow

Example:

```bash
./install-stavrobot.sh --print-shelley-mode-status
```

Recommended output should include at least:

- whether managed Shelley mode is configured locally
- tracked Shelley repo URL and branch
- recorded upstream Shelley commit/hash
- local Shelley checkout path
- local Shelley binary path
- canonical bridge path
- available profile names
- whether an upstream check was performed
- whether the local managed state appears current or stale

### 4. Profile refresh / override flow

Example:

```bash
./install-stavrobot.sh \
  --with-shelley-stavrobot-mode \
  --shelley-profile-name lab \
  --shelley-base-url http://localhost:8001 \
  --shelley-config-path /srv/stavrobot-lab/data/main/config.toml
```

Recommended effect:

- preserve the Shelley rebuild if still current
- create or update only the named installer-managed profile if the build itself does not need refresh
- avoid rewriting conversation metadata directly; conversations should continue to refer to profile names and can switch later within Shelley

## Recommended precedence rules

1. explicit CLI flags override stored installer state
2. stored installer state overrides inferred defaults
3. inferred defaults override generic hardcoded defaults

Specific recommendations:

- if both `--shelley-config-path` and `--shelley-stavrobot-dir` are provided, prefer explicit `--shelley-config-path`
- if `--shelley-profile-name` is omitted, default to `local-default`
- if `--shelley-dir` is omitted on first enable, require an explicit path or choose one documented default consistently
- if `--with-shelley-stavrobot-mode` and `--disable-shelley-mode` are both passed, fail fast as conflicting flags
- if `--print-shelley-mode-status` is combined with mutating Shelley flags, either reject the combination or document a strict precedence clearly

## Recommended failure policy

Hard fail on:

- missing Shelley checkout path for first-time enable when no default is available
- Shelley upstream fetch failure during an enabled refresh path unless `--skip-shelley-upstream-check` was explicitly used
- Shelley build failure
- missing canonical bridge script
- invalid profile inputs
- unreadable Stavrobot config path when a profile requires it
- malformed or unreadable `state/shelley-mode-build.json` during refresh/status unless operator explicitly requests reinitialization behavior later

Soft warn on:

- upstream check skipped deliberately
- profile already exists and is being refreshed in place
- Shelley upstream changed but operator only requested read-only status
- additional profiles exist but are not referenced by any current Shelley conversations

## Recommended relation to future Shelley conversation UX

The installer CLI should prepare capability, not mutate user conversations directly.

Meaning:

- installer builds or refreshes the Shelley variant
- installer records bridge profiles and upstream hash state
- Shelley UI/runtime later lets the user choose Stavrobot mode per conversation
- Shelley conversation metadata then stores only the chosen profile name and remote conversation mapping

That keeps the installer operational and machine-scoped while keeping conversation selection and per-thread behavior inside Shelley where it belongs.


## Draft Shelley-side conversation lifecycle recommendation

The eventual Shelley rebuild should implement optional Stavrobot mode as a small per-conversation state machine, not just as a raw boolean.

Recommended minimum states:

1. normal
2. Stavrobot configured, not yet mapped
3. Stavrobot mapped and active
4. Stavrobot degraded / attention-needed

Recommended implementation implications:

- selecting Stavrobot mode should require only a valid installer-managed bridge profile, not a pre-existing remote conversation ID
- the first successful remote turn should create or confirm the remote Stavrobot `conversation_id`
- subsequent turns should reuse that mapping through the canonical bridge
- failures should move the conversation into a degraded actionable state rather than silently falling back to normal direct-model behavior
- reset/remap should be explicit user actions

Recommended operational rule:

- installer prepares the Shelley build and local profile definitions
- Shelley owns per-conversation state transitions and remote mapping lifecycle

This keeps the installer and Shelley responsibilities cleanly separated while preserving a usable conversation-centric mode design.


## Draft official Shelley seam recommendation

When the actual Shelley-side patch is attempted, the cleanest likely ownership split is:

1. conversation metadata/options handling decides whether a conversation is in Stavrobot mode
2. conversation runtime dispatch sends Stavrobot-mode turns to a dedicated runner rather than the normal provider path
3. the existing Shelley in-flight `Agent Working...` behavior is reused while waiting on the Stavrobot bridge/result
4. a message/content mapping layer converts bridge results into Shelley's native message/display structures
5. optional remote history/event reconciliation remains a separate later layer

Important consequence for the shell integration contract:

- `shelley-stavrobot-bridge.sh` should remain the only Shelley-facing local contract
- but that bridge should be allowed to evolve beyond plain response text into a stable structured output mode when Shelley is ready to preserve richer markdown/media/tool semantics

That preserves the current minimal integration while keeping a clear path toward Shelley-native rich rendering and trace visibility later.


## Draft Shelley UX recommendation for Stavrobot mode

The first Shelley-side UX can stay compact while still being clear.

Recommended minimum UX elements:

- conversation mode selector with `Default` and `Stavrobot`
- installer-managed Stavrobot profile selector when Stavrobot mode is chosen
- reuse of Shelley's existing `Agent Working...` indicator while waiting on the bridge/result
- a mode-aware context label such as `Context managed by Stavrobot`
- explicit degraded-state messaging with actionable recovery options
- explicit `Reset remote mapping` action

Recommended UX discipline:

- keep Stavrobot-specific controls mostly in conversation settings/details, not scattered throughout the composer
- make retrieval/cross-conversation recall explicit when used
- design future rich markdown/media/tool rendering to flow through Shelley's native content UI rather than a separate raw bridge/debug surface


## Draft phased Shelley execution roadmap

Recommended sequence for the eventual Shelley-side work:

### S1

- minimal per-conversation Stavrobot mode
- canonical bridge invocation
- conversation mapping persistence
- reused `Agent Working...`
- compact mode-aware UX

### S2

- richer structured output from `shelley-stavrobot-bridge.sh`
- improved markdown/media/tool fidelity

### S3

- optional remote history/event reconciliation
- richer diagnostics and trace visibility

### S4

- first validate whether Stavrobot itself already handles cross-conversation recall well enough when asked naturally
- only add explicit Shelley-side retrieval orchestration if testing shows that native Stavrobot recall is insufficient

Important recommendation:

- do not assume Shelley must own cross-conversation retrieval before testing Stavrobot's native behavior more deeply
- if Stavrobot already answers broader recall prompts well enough, that is one less integration layer to build and maintain


## Draft validation checklist summary for Shelley phases

Each Shelley-side phase should have explicit acceptance checks.

### S1 checks

- per-conversation mode selection works
- first-turn remote mapping works
- ongoing mapped continuation works
- existing `Agent Working...` is reused
- degraded-state handling is actionable
- reset/remap behavior is explicit and correct

### S2 checks

- canonical bridge exposes stable structured output
- Shelley preserves markdown/media/tool fidelity better than plain response-only mode
- single-bridge contract remains intact

### S3 checks

- remote history/event reconciliation improves diagnostics and trace visibility
- reconciliation remains separate from the core send-turn path

### S4 checks

- first test whether Stavrobot already handles cross-conversation recall well enough naturally
- only proceed to explicit Shelley-side retrieval machinery if real testing shows native Stavrobot recall is inadequate

Recommended principle:

- every later Shelley phase should be justified by validation evidence, not just architectural neatness

Strategic follow-up artifact:

- `docs/SHELLEY_STRATEGIC_GAP_AUDIT.md` now summarizes the remaining post-S1 gaps, especially S2 rich-content fidelity, S4 recall validation, Stavrobot-mode-only backend-model UX placement, and mobile/responsive preservation rules
- recommended next order remains: narrow S2 scope first, then collect S4 recall evidence before deciding on any Shelley-side retrieval layer


## Compact Shelley handoff summary

Shortest execution-oriented summary:

- keep Shelley Stavrobot integration optional
- implement it per conversation
- integrate above the normal model/provider layer
- use only `shelley-stavrobot-bridge.sh` as the Shelley-facing local contract
- keep conversation metadata small and secret-free
- keep installer-managed rebuild/profile state separate
- reuse Shelley's existing `Agent Working...`
- evolve the canonical bridge toward structured output later for markdown/media/tool fidelity
- validate Stavrobot's native cross-conversation recall behavior before building an extra Shelley retrieval layer

Recommended first implementation target remains S1 only.


## S1 disposable spike status update

A real disposable S1 spike in `/tmp/shelley-official` has now validated the core seam.

Validated outcome:

- optional per-conversation Stavrobot mode can be implemented in official Shelley by branching in the conversation handler/runtime path
- `conversation_options` can carry the minimal Stavrobot metadata shape cleanly
- existing Shelley message recording, stream updates, and working-state UX can be reused
- first-turn remote mapping and second-turn continuation both worked against the local Stavrobot stack

Implication:

- the project should now prioritize implementation/rebuild execution over additional broad architecture planning
- the main remaining work is converting the disposable spike knowledge into a managed, repeatable Shelley rebuild/update path and then improving fidelity incrementally

Implementation-facing extraction artifact:

- `docs/SHELLEY_S1_SPIKE_EXTRACTION.md`

Use that artifact as the reference for:

- exact files/layers touched in the disposable spike
- what the spike proved architecturally
- what was disposable scaffolding and must be replaced
- what the managed S1 rebuild path should reproduce cleanly

Managed rebuild contract artifact:

- `docs/SHELLEY_MANAGED_REBUILD_CONTRACT.md`

Use that artifact as the reference for:

- installer-owned rebuild provenance state
- installer-owned bridge profile state
- refresh/staleness logic
- future Shelley-mode installer flag behavior


## Stavrobot-mode-only backend model control note

A possible later Shelley feature is operator-facing Stavrobot backend model control from within Shelley.

Current recommendation:

- treat it as a **Stavrobot-mode-only** admin/operator feature
- do not change ordinary upstream Shelley behavior when Stavrobot mode is off
- do not store shared backend model choice in per-conversation metadata unless Stavrobot later supports true per-conversation model selection
- prefer a controlled local helper/service boundary for config mutation and restart/recreate actions
- reuse this repo's existing OpenRouter free-model fetch/filter logic rather than duplicating it in Shelley

Concrete review artifact:

- `docs/SHELLEY_STAVROBOT_MODEL_CONTROL.md`

Validation follow-up:

- `docs/SHELLEY_STAVROBOT_MODEL_CONTROL_VALIDATION.md` now records that a tested Stavrobot model change worked via `config.toml` mutation plus `docker compose restart app`, without requiring a full image rebuild
- this suggests future Shelley-side model control should be treated as runtime admin control rather than as part of the Shelley rebuild path

Helper-contract follow-up:

- `docs/SHELLEY_STAVROBOT_MODEL_CONTROL_HELPER_CONTRACT.md` now defines the concrete local helper shape for future Shelley-triggered Stavrobot model control
- the OpenRouter model picker should only surface when active Stavrobot config is actually using `provider = "openrouter"` with corresponding auth/config
- the observed duplicate `openrouter/free` response should currently be treated as an issue with unclear cause, not as model-specific proof

Disposable helper follow-up:

- `manage-stavrobot-model.sh` and `py/stavrobot_model_control.py` now provide a validated first local prototype for Stavrobot model inspection/list/apply flows
- the prototype was validated against `/tmp/stavrobot` for `get-current`, gated `list-openrouter-free`, `apply --model openrouter/free`, and restore back to the prior model
- it should still be treated as a prototype pending TOML-edit hardening, privilege-boundary hardening, and Shelley UI wiring
- near-term operator UX should expose this as a documented standalone helper rather than mixing shared-backend model mutation into the main installer config flow
- lightweight regression coverage should protect current helper behavior before any future Shelley-native admin-panel wiring

Managed recipe follow-up:

- `docs/SHELLEY_MANAGED_PATCH_REBUILD_RECIPE.md` now serves as the concrete operational recipe for reproducing the validated S1 patch shape in an official Shelley checkout
- it records the recommended managed checkout path, exact build commands, patch-owned upstream files, and minimum runtime smoke validation flow

Managed asset follow-up:

- `patches/shelley/s1-stavrobot-mode-disposable-shape.patch` now captures the validated disposable upstream S1 diff as a repo-owned starting patch artifact
- `smoke-test-shelley-managed-s1.sh` now captures the minimum isolated normal+Stavrobot-mode smoke flow as a repo-owned validation driver

Live-cutover follow-up:

- the managed Shelley rebuild path should eventually include an explicit systemd cutover phase for the real `/usr/local/bin/shelley` runtime
- that phase should stop `shelley.socket` and `shelley.service`, preserve a one-time original-binary backup, install the rebuilt binary, restart both units, and perform live post-cutover validation
- this deployment/cutover phase should remain distinct from the isolated build and smoke-validation phase

Managed patch cleanup follow-up:

- `patches/shelley/README.md` now explains why the captured disposable-shape patch is only a starting artifact and what must be cleaned before it becomes the real managed patch set
- `docs/SHELLEY_MANAGED_PATCH_CLEANUP_PLAN.md` now defines the concrete cleanup targets, especially replacing hardcoded bridge/profile assumptions and isolating Stavrobot runtime integration from bulky route handlers

Bridge-resolution follow-up:

- `docs/SHELLEY_BRIDGE_PROFILE_RESOLUTION_CONTRACT.md` now defines the narrow installer-managed profile-state contract the cleaned Shelley patch should read to resolve `bridge_profile` into bridge path, base URL, config path, and default args
- the repo now also includes a prototype executable version of that contract at `state/shelley-bridge-profiles.json`, `py/shelley_bridge_profiles.py`, and `manage-shelley-bridge-profiles.sh`
- this is the key contract needed to remove the disposable patch's hardcoded bridge path and `local-default` mapping assumptions

Cleaned-patch-shape follow-up:

- `docs/SHELLEY_CLEANED_PATCH_SERIES_SHAPE.md` now maps the captured disposable patch into a likely maintainable patch series, keeping metadata/schema pieces close to validated shape while moving bridge/profile/runtime logic into a focused Shelley-side integration unit

## Shelley cleaned managed patch-series skeleton

The repo now also contains a first owned patch-series skeleton under:

- `patches/shelley/series/`

This is not the final smoke-validated maintained patch set yet, though the split prototype series has now been replay/apply validated in order against a fresh upstream Shelley checkout.

It exists to lock in the intended maintained split:

1. metadata / SQL / UI
2. conversation manager support
3. route branching only
4. focused Stavrobot runtime integration unit

Why this matters:

- it keeps the future maintained patch from collapsing back into one handler-heavy mixed diff
- it makes the next implementation step concrete, especially around the proposed `server/stavrobot.go` runtime boundary
- it gives future rebuild automation a cleaner owned target than the disposable patch alone

## Shelley patch-4 runtime apply scaffold

The repo now also contains a focused apply scaffold for the cleaned runtime-unit extraction at:

- `patches/shelley/series/0004-stavrobot-runtime-unit.patch-plan.md`

That scaffold defines the likely first maintained implementation move inside Shelley itself:

- introduce `server/stavrobot.go`
- move profile loading/resolution there
- move bridge execution there
- move turn orchestration there
- leave `server/handlers.go` as thin branching + HTTP response translation only

## First managed `/opt/shelley` runtime prototype

A managed upstream checkout under `/opt/shelley` has now been used to produce the first cleaned-runtime prototype diff:

- `patches/shelley/s1-stavrobot-mode-cleaned-runtime-prototype.patch`

That prototype artifact has now also had a first light hardening pass so the focused `server/stavrobot.go` runtime unit is less text-locked at its result boundary while preserving current S1 behavior.

That prototype currently includes:

- metadata / SQL / UI support needed for Stavrobot mode
- conversation-manager support
- thin handler branching
- a focused `server/stavrobot.go` runtime unit

It has also been through targeted validation in the managed checkout via:

- `go test ./server/... ./db/...`

with the note that local UI assets had to be built in the managed checkout for server tests to pass.

The split prototype series has now also been replay/apply validated in order against a fresh upstream Shelley checkout from `/tmp/shelley-official` commit `5b07230`:

- `0001` → `0004` each passed `git apply --check`
- all four patches applied cleanly in sequence
- the final applied owned files matched the managed `/opt/shelley` prototype state
- after satisfying the normal upstream UI build prerequisite, fresh-checkout `go test ./server/... ./db/...` also passes
- `validate-shelley-patch-series.sh` now captures this replay/apply + UI-build + Go-test flow as a repo-owned validator
- the higher-level isolated managed rebuild flow has now also been revalidated on `/opt/shelley` using rebuilt UI/sqlc/templates/binary plus `smoke-test-shelley-managed-s1.sh` against `/var/lib/stavrobot-installer/shelley-bridge-profiles.json`
- `refresh-shelley-managed-s1.sh` now captures the managed patch/rebuild/smoke/state-update flow as a repo-owned helper
- `print-shelley-managed-status.sh` now captures the read-only managed status/reporting path as a repo-owned helper
- `install-stavrobot.sh` now exposes the current managed Shelley path directly via `--print-shelley-mode-status` and `--refresh-shelley-mode`, including machine-readable `--print-shelley-mode-status --json`
- README and rebuild docs now also include a compact operator-facing command/checklist section for the managed Shelley mode flow
- managed Shelley status reporting now distinguishes `current` vs `current-dirty` checkout state so rebuild-needed output reflects dirty managed checkouts too
- managed rebuild state now also records `build.checkout_dirty_at_rebuild` so operator intent/history is visible in later status output
- human-readable managed status now surfaces dirty recorded rebuild provenance as an explicit warning, and reports `unknown` for older state files that predate that field
- a lightweight repo-owned `tests/run.sh` driver now exists for helper/status regression checks, including managed-status output-shape coverage, installer guardrails/config modes/OpenRouter flow, and bridge-profile helper coverage
- the installer now also enforces explicit conflict/precedence guardrails for Shelley-only vs normal installer mutation flows
