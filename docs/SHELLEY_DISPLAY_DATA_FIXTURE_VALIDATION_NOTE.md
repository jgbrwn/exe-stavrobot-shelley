# Shelley display_data fixture validation note

## Purpose

Capture the now-available deterministic validation path for the managed Shelley runtime behavior that persists Stavrobot compact display hints into real message `display_data`.

This avoids future sessions needing to rediscover how to prove the behavior when live Stavrobot turns happen to return plain markdown/text only.

## What is now available

A test-only fixture path exists in the canonical bridge:

- `STAVROBOT_BRIDGE_FIXTURE=tool_summary`

When enabled, bridge chat output injects a deterministic `display.tool_summary` only if no real summary is already present.

This keeps normal runtime behavior unchanged while making strict smoke assertions reproducible.

## Strict proof command

Run managed refresh/smoke with strict display-hint requirements plus the fixture:

```bash
./install-stavrobot.sh \
  --refresh-shelley-mode \
  --expect-shelley-display-data \
  --require-shelley-display-hints \
  --shelley-bridge-fixture tool_summary
```

Equivalent direct refresh helper form:

```bash
./refresh-shelley-managed-s1.sh \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --smoke-expect-display-data \
  --smoke-require-display-hints \
  --smoke-bridge-fixture tool_summary
```

## Expected result

- smoke passes
- strict display-hint requirement is satisfied
- Stavrobot assistant rows in the smoke DB show:
  - non-empty `user_data.stavrobot.raw_payload.display.tool_summary`
  - non-null persisted `display_data.tool_summary`

## Lightweight regression coverage

The repo now has direct fixture regression coverage without requiring live Stavrobot/tool behavior:

```bash
./tests/run.sh test-shelley-stavrobot-bridge-fixture.sh
```

That test verifies:

- no synthetic `display` block in normal mode
- synthetic `display.tool_summary` appears in fixture mode

## Scope reminder

This fixture is a validation aid only.

- It should not be treated as production content behavior.
- It should be used to prove runtime persistence plumbing deterministically.
- Live/non-fixture behavior remains governed by real bridge/Stavrobot payloads.

## Live non-fixture validation update

The bridge now attempts live `tool_summary` enrichment from the events endpoint whenever chat output does not already include usable event/display summary fields.

Practical consequence:

- strict smoke runs with `--expect-display-data --require-display-hints` can now pass without fixture mode when Stavrobot event data is available for the sampled conversation
- fixture mode remains useful as a deterministic fallback for CI/POC environments where live behavior may vary

## Narrow media/image follow-on note

The bridge now also includes a narrow image/media-reference extraction path.

When obvious image URLs are present (for example `.png`/`.jpg` links in payload fields, response text, or recent event summaries), bridge output includes:

```json
"artifacts": [
  {"kind": "image", "url": "https://...", "title": ""}
]
```

This remains intentionally conservative and URL-based for now.
It is meant to support managed runtime `media_refs` preservation and later promotion into richer native Shelley media handling.

## Media-ref persistence validation

Managed smoke now also supports media-ref assertions:

```bash
./install-stavrobot.sh \
  --refresh-shelley-mode \
  --expect-shelley-media-refs
```

Strict mode:

```bash
./install-stavrobot.sh \
  --refresh-shelley-mode \
  --expect-shelley-media-refs \
  --require-shelley-media-refs
```

Current rule:

- assertion is required only when sampled raw bridge payloads include image/media hints (`content.kind=image_ref` or `artifacts.kind=image` with URL)
- strict mode fails when no such hints are observed

## Raw media fixture mode (phase-1 contract proof)

A second deterministic fixture mode now exists for bounded raw media:

- `STAVROBOT_BRIDGE_FIXTURE=raw_media_image`

When enabled, bridge chat output injects a compact inline raw image artifact only if no real image artifact is already present.

Example emitted artifact shape:

```json
{
  "kind": "image",
  "mime_type": "image/png",
  "transport": "raw_inline_base64",
  "byte_length": 17,
  "data_base64": "Zml4dHVyZS1yYXctaW1hZ2U=",
  "title": "fixture raw media image for managed smoke validation"
}
```

## Live managed smoke proof for raw-inline `media_refs`

Direct smoke command used against managed `/opt/shelley` binary:

```bash
./smoke-test-shelley-managed-s1.sh \
  --shelley-dir /opt/shelley \
  --shelley-bin /opt/shelley/bin/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --port 8890 \
  --db-path /tmp/shelley-smoke-debug.db \
  --tmux-session shelley-smoke-debug \
  --expect-media-refs \
  --require-media-refs \
  --bridge-fixture raw_media_image
```

Proof query:

```bash
sqlite3 -json /tmp/shelley-smoke-debug.db \
  "SELECT sequence_id, type, display_data FROM messages WHERE conversation_id='CONV_ID' AND type='agent' ORDER BY sequence_id;"
```

Expected evidence in persisted `display_data.media_refs`:

- `transport = raw_inline_base64`
- non-empty `data_base64`
- `mime_type = image/png`
- positive `byte_length`

## Port-collision diagnostics update

Managed smoke helpers now fail fast when the smoke port is already in use.

- `refresh-shelley-managed-s1.sh` checks `--smoke-port` before starting smoke.
- `smoke-test-shelley-managed-s1.sh` checks the target port before server start and prints listener details (`ss`/`lsof`) when occupied.
- smoke cleanup now also warns if a listener still exists on the smoke port after tmux shutdown.

This prevents ambiguous failures where the shell session starts but Shelley exits immediately with bind errors.

## Refresh-helper strict raw-media proof command

With current updates, managed refresh can run a deterministic strict raw-media proof directly:

```bash
./refresh-shelley-managed-s1.sh \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --smoke-port 8891 \
  --smoke-expect-media-refs \
  --smoke-require-media-refs \
  --smoke-bridge-fixture raw_media_image
```

Notes:

- refresh helper now fails fast if `--smoke-port` is already listening
- when default smoke DB/session values are used, refresh now auto-suffixes them with port+timestamp to avoid stale-collision confusion
- on smoke failure, refresh prints the exact smoke session/db/port tuple for fast diagnosis

## Runtime native-mapping/rejection smoke assertions (new)

Managed smoke helpers now support two additional runtime-focused assertions:

- `--expect-native-raw-media-gating` (+ optional strict `--require-native-raw-media-hints`)
  - validates phase-2 gate behavior: native raw-media mapping is allowed only when no assistant text content exists
- `--expect-raw-media-rejection` (+ optional strict `--require-raw-media-rejection-hints`)
  - validates invalid raw-inline artifacts are rejected non-fatally (no persisted invalid raw media ref + unsupported-kind reason evidence)

Deterministic fixture aids were added for this:

- `STAVROBOT_BRIDGE_FIXTURE=runtime_raw_media_only`
- `STAVROBOT_BRIDGE_FIXTURE=runtime_invalid_raw_media`

Plus additional rejection-shape fixtures:

- `STAVROBOT_BRIDGE_FIXTURE=runtime_unsupported_raw_mime`
- `STAVROBOT_BRIDGE_FIXTURE=runtime_oversize_raw_media`

Example direct smoke command (gate proof):

```bash
./smoke-test-shelley-managed-s1.sh \
  --shelley-dir /opt/shelley \
  --shelley-bin /opt/shelley/bin/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --port 8892 \
  --db-path /tmp/shelley-smoke-gate.db \
  --tmux-session shelley-smoke-gate \
  --bridge-fixture runtime_raw_media_only \
  --expect-native-raw-media-gating \
  --require-native-raw-media-hints
```

Example rejection proof command:

```bash
./smoke-test-shelley-managed-s1.sh \
  --shelley-dir /opt/shelley \
  --shelley-bin /opt/shelley/bin/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --port 8893 \
  --db-path /tmp/shelley-smoke-reject.db \
  --tmux-session shelley-smoke-reject \
  --bridge-fixture runtime_invalid_raw_media \
  --expect-raw-media-rejection \
  --require-raw-media-rejection-hints
```

## Latest managed proof checkpoint (commit `d0af7e8`)

The following strict managed refresh proofs were run successfully against `/opt/shelley` with the current patch series applied:

### 1) Runtime native raw-media gate proof

Command:

```bash
./refresh-shelley-managed-s1.sh \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --smoke-port 8892 \
  --smoke-db-path /tmp/shelley-proof-gate.db \
  --smoke-tmux-session shelley-proof-gate \
  --smoke-expect-native-raw-media-gating \
  --smoke-require-native-raw-media-hints \
  --smoke-expect-media-refs \
  --smoke-require-media-refs \
  --smoke-bridge-fixture runtime_raw_media_only
```

Observed DB evidence (`/tmp/shelley-proof-gate.db`):

- assistant rows had `raw_payload.content=[]` + one raw-inline artifact
- `llm_data.Content` contained native media entries (`MediaType` + `Data`)
- `display_data.media_refs` contained persisted raw media refs

### 2) Runtime invalid raw-media rejection proof

Command:

```bash
./refresh-shelley-managed-s1.sh \
  --allow-dirty \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --smoke-port 8893 \
  --smoke-db-path /tmp/shelley-proof-reject-invalid.db \
  --smoke-tmux-session shelley-proof-reject-invalid \
  --smoke-expect-raw-media-rejection \
  --smoke-require-raw-media-rejection-hints \
  --smoke-bridge-fixture runtime_invalid_raw_media
```

Observed DB evidence (`/tmp/shelley-proof-reject-invalid.db`):

- `unsupported_kinds` included `artifact:image:invalid raw media base64`
- `display_data.media_refs` had no raw inline entry
- assistant rows remained recorded (non-fatal degradation)

### 3) Runtime unsupported-mime rejection proof

Command:

```bash
./refresh-shelley-managed-s1.sh \
  --allow-dirty \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --smoke-port 8894 \
  --smoke-db-path /tmp/shelley-proof-reject-unsupported.db \
  --smoke-tmux-session shelley-proof-reject-unsupported \
  --smoke-expect-raw-media-rejection \
  --smoke-require-raw-media-rejection-hints \
  --smoke-bridge-fixture runtime_unsupported_raw_mime
```

Observed DB evidence (`/tmp/shelley-proof-reject-unsupported.db`):

- `unsupported_kinds` included `artifact:image:unsupported raw media mime`
- `display_data.media_refs` had no raw inline entry
- assistant rows remained recorded (non-fatal degradation)

### 4) Runtime oversize rejection proof

Command:

```bash
./refresh-shelley-managed-s1.sh \
  --allow-dirty \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --smoke-port 8895 \
  --smoke-db-path /tmp/shelley-proof-reject-oversize.db \
  --smoke-tmux-session shelley-proof-reject-oversize \
  --smoke-expect-raw-media-rejection \
  --smoke-require-raw-media-rejection-hints \
  --smoke-bridge-fixture runtime_oversize_raw_media
```

Observed DB evidence (`/tmp/shelley-proof-reject-oversize.db`):

- `unsupported_kinds` included `artifact:image:raw media payload exceeds max bytes`
- `display_data.media_refs` had no raw inline entry
- assistant rows remained recorded (non-fatal degradation)

## Authoritative strict raw-media profile (current default recommendation)

To avoid drift between sessions/operators, use the managed strict profile as the default runtime proof entrypoint.

Installer-managed form:

```bash
./install-stavrobot.sh \
  --refresh-shelley-mode \
  --sync-shelley-upstream-ff-only \
  --strict-shelley-raw-media-profile
```

Direct helper form:

```bash
./run-shelley-managed-strict-raw-media-proof.sh \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json
```

This runs the deterministic fixture matrix in sequence:

- `runtime_raw_media_only`
- `runtime_invalid_raw_media`
- `runtime_unsupported_raw_mime`
- `runtime_oversize_raw_media`

with strict assertions pre-wired for each case.

## Managed runtime smoke contract CI policy

CI authoritative required-runtime entrypoints:

- `./ci/check-memory-suitability-runtime-prereqs.sh`
- `./ci/run-memory-suitability-required-runtime.sh`

This is the canonical S2+S4 memory-evidence hygiene lane for required-runtime environments. The preflight checker hard-fails when managed runtime prerequisites are missing; the gate entrypoint delegates to the aggregate helper with `--required-runtime` and should be treated as failing unless all three contract lanes pass.

Current test behavior:

- `tests/test-shelley-managed-smoke-raw-media-runtime-contract.sh`
- `tests/test-shelley-managed-smoke-s2-narrow-fidelity-contract.sh`

Both tests:

- default mode remains skip-safe when `/opt/shelley` runtime prerequisites are missing/unpatched
- support `REQUIRE_PATCHED_MANAGED_RUNTIME=1` to enforce a required-runtime lane (test fails instead of skip)

Example required-runtime invocations:

```bash
REQUIRE_PATCHED_MANAGED_RUNTIME=1 \
  ./tests/run.sh test-shelley-managed-smoke-raw-media-runtime-contract.sh

REQUIRE_PATCHED_MANAGED_RUNTIME=1 \
  ./tests/run.sh test-shelley-managed-smoke-s2-narrow-fidelity-contract.sh
```

## Latest strict-profile execution checkpoint (post-profile wiring)

Managed strict profile was executed successfully via refresh helper after introducing the authoritative profile flag:

```bash
./refresh-shelley-managed-s1.sh \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --smoke-port 8892 \
  --smoke-strict-raw-media-profile
```

When the latest upstream Shelley is required as part of refresh, add:

```bash
--sync-upstream-ff-only
```

Observed pass bundle DB paths:

- `/tmp/shelley-stavrobot-managed-test-1773933684-runtime_raw_media_only.db`
- `/tmp/shelley-stavrobot-managed-test-1773933684-runtime_invalid_raw_media.db`
- `/tmp/shelley-stavrobot-managed-test-1773933684-runtime_unsupported_raw_mime.db`
- `/tmp/shelley-stavrobot-managed-test-1773933684-runtime_oversize_raw_media.db`

Required-runtime lane check also passed:

```bash
REQUIRE_PATCHED_MANAGED_RUNTIME=1 \
  ./tests/run.sh test-shelley-managed-smoke-raw-media-runtime-contract.sh
```

## Minimal release-checklist snippet

Use this exact two-lane wording to avoid drift across future sessions:

1. **Dev lane (default portable lane):** run managed runtime contract smoke in skip-safe mode (both strict raw-media and S2 narrow-fidelity contracts).
2. **Release lane (required-runtime lane):** rerun both tests with `REQUIRE_PATCHED_MANAGED_RUNTIME=1`; treat any skip-precondition as failure.

Concrete commands:

```bash
./tests/run.sh test-shelley-managed-smoke-raw-media-runtime-contract.sh
./tests/run.sh test-shelley-managed-smoke-s2-narrow-fidelity-contract.sh
REQUIRE_PATCHED_MANAGED_RUNTIME=1 ./tests/run.sh test-shelley-managed-smoke-raw-media-runtime-contract.sh
REQUIRE_PATCHED_MANAGED_RUNTIME=1 ./tests/run.sh test-shelley-managed-smoke-s2-narrow-fidelity-contract.sh
```

Process cleanup note:

- smoke helpers always run under isolated tmux sessions and now attempt explicit post-run listener cleanup on the smoke port
- cleanup flow is: kill tmux session, wait briefly, then TERM/KILL lingering shelley listener PIDs bound to the smoke port if needed
- remaining listeners still produce explicit warnings with port listener details
- hard safety rule: smoke/test helpers reject port `9999` (reserved for operator/dev Shelley) and profile helpers reject base-port ranges that would overlap `9999`

## S2 narrow fidelity fixture proof (markdown + tool summary)

A deterministic fixture mode is available for the first narrow S2 runtime-adaptation proof:

- `STAVROBOT_BRIDGE_FIXTURE=s2_markdown_tool_summary`

It forces markdown-first `content[]` with a deterministic heading and ensures compact `display.tool_summary` in bridge output.

Managed smoke command:

```bash
./smoke-test-shelley-managed-s1.sh \
  --shelley-dir /opt/shelley \
  --shelley-bin /opt/shelley/bin/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --port 8896 \
  --db-path /tmp/shelley-smoke-s2-markdown.db \
  --tmux-session shelley-smoke-s2-markdown \
  --bridge-fixture s2_markdown_tool_summary \
  --expect-s2-markdown-tool-summary \
  --require-s2-markdown-tool-summary-hints
```

Installer equivalent:

```bash
./install-stavrobot.sh \
  --refresh-shelley-mode \
  --expect-shelley-s2-markdown-tool-summary \
  --require-shelley-s2-markdown-tool-summary-hints \
  --shelley-bridge-fixture s2_markdown_tool_summary
```

Expected persistence evidence:

- `user_data.stavrobot.raw_payload.content` includes markdown item with `## S2 fixture heading`
- `llm_data.Content` includes assistant text containing `## S2 fixture heading`
- `display_data.tool_summary` is present and non-empty

## S2 raw-events -> tool_summary fallback fixture proof

A second deterministic S2 fixture mode validates runtime fallback behavior when bridge payload has raw events but no direct `display.tool_summary`:

- `STAVROBOT_BRIDGE_FIXTURE=s2_markdown_raw_tool_events`

Managed smoke command:

```bash
./smoke-test-shelley-managed-s1.sh \
  --shelley-dir /opt/shelley \
  --shelley-bin /opt/shelley/bin/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --port 8897 \
  --db-path /tmp/shelley-smoke-s2-raw-fallback.db \
  --tmux-session shelley-smoke-s2-raw-fallback \
  --bridge-fixture s2_markdown_raw_tool_events \
  --expect-s2-tool-summary-raw-fallback \
  --require-s2-tool-summary-raw-fallback-hints
```

Installer equivalent:

```bash
./install-stavrobot.sh \
  --refresh-shelley-mode \
  --expect-shelley-s2-tool-summary-raw-fallback \
  --require-shelley-s2-tool-summary-raw-fallback-hints \
  --shelley-bridge-fixture s2_markdown_raw_tool_events
```

Expected persistence evidence:

- `user_data.stavrobot.raw_payload.raw.events` exists and is non-empty
- `user_data.stavrobot.raw_payload.display.tool_summary` is absent/empty
- persisted `display_data.tool_summary` is present and non-empty (derived fallback)

## S2 narrow-fidelity fixture proof profile

An aggregate deterministic S2 proof helper is available for managed Shelley smoke validation:

- `./run-shelley-managed-s2-narrow-fidelity-proof.sh`

Fixture matrix covered by this profile:

- `s2_markdown_tool_summary`
- `s2_markdown_media_refs`
- `s2_markdown_raw_tool_events`

Installer/refresh entrypoints:

```bash
./install-stavrobot.sh --refresh-shelley-mode --s2-shelley-narrow-fidelity-profile

./refresh-shelley-managed-s1.sh \
  --smoke-s2-narrow-fidelity-profile
```

Guardrails mirror strict raw-media profile behavior:

- incompatible with explicit per-fixture smoke expect/require flags
- incompatible with explicit `--(smoke-)bridge-fixture`
- incompatible with strict raw-media profile mode
- currently does not accept direct smoke db/session overrides in profile mode

## Latest S2 narrow-fidelity profile execution checkpoint (commit `35ae5a9`)

Managed refresh helper proof run completed successfully against `/opt/shelley` using the new aggregate S2 profile:

```bash
./refresh-shelley-managed-s1.sh \
  --allow-dirty \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --smoke-port 8902 \
  --smoke-s2-narrow-fidelity-profile
```

Observed pass bundle DB paths:

- `/tmp/shelley-stavrobot-managed-s2-test-1774032692-s2_markdown_tool_summary.db`
- `/tmp/shelley-stavrobot-managed-s2-test-1774032692-s2_markdown_media_refs.db`
- `/tmp/shelley-stavrobot-managed-s2-test-1774032692-s2_markdown_raw_tool_events.db`

Fixture-level assertions covered in this run:

- markdown fallback + compact `display.tool_summary` persistence
- markdown fallback + `display_data.media_refs` persistence from both content + artifact image refs
- `raw.events` → persisted `display_data.tool_summary` fallback derivation

## S2 markdown + media-ref persistence fixture proof

A third deterministic S2 fixture mode now validates markdown-first media-reference persistence behavior:

- `STAVROBOT_BRIDGE_FIXTURE=s2_markdown_media_refs`

It emits:

- markdown `content[]` with `## S2 fixture heading`
- deterministic `content.kind=image_ref` URL
- deterministic `artifacts.kind=image` URL

Managed smoke command:

```bash
./smoke-test-shelley-managed-s1.sh \
  --shelley-dir /opt/shelley \
  --shelley-bin /opt/shelley/bin/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --port 8898 \
  --db-path /tmp/shelley-smoke-s2-media-refs.db \
  --tmux-session shelley-smoke-s2-media-refs \
  --bridge-fixture s2_markdown_media_refs \
  --expect-s2-markdown-media-refs \
  --require-s2-markdown-media-refs-hints
```

Installer equivalent:

```bash
./install-stavrobot.sh \
  --refresh-shelley-mode \
  --expect-shelley-s2-markdown-media-refs \
  --require-shelley-s2-markdown-media-refs-hints \
  --shelley-bridge-fixture s2_markdown_media_refs
```

Expected persistence evidence:

- `user_data.stavrobot.raw_payload.content` contains markdown + `image_ref` item
- `user_data.stavrobot.raw_payload.artifacts` contains URL image artifact
- persisted `display_data.media_refs` contains both:
  - `kind=image_ref` for content reference URL
  - `kind=artifact:image` for artifact URL
- `llm_data.Content` still contains assistant text fallback with `## S2 fixture heading`

## S4 recall validation runner (new)

A first repeatable managed-Shelley S4 evidence runner is now available:

- `./run-shelley-managed-s4-recall-validation.sh`

It executes a compact four-scenario probe matrix from `docs/SHELLEY_S4_RECALL_VALIDATION_TEMPLATE.md` against isolated managed Shelley runtime state and emits a machine-readable report:

- default report path: `state/s4-recall-validation-last.json`
- report includes: metadata, seeded facts, conversation IDs, per-probe answers + rubric classifications, and provisional `S4A`/`S4B` heuristic outcome

Safety/operability rules:

- uses isolated tmux-backed server with dedicated DB/log paths
- rejects port `9999` (reserved operator/dev Shelley)
- optional strict lane `--require-remote-isolation` fails if seeded Shelley conversations are not mapped to distinct remote Stavrobot conversation IDs
- `--remote-isolation-profile-session` enables deterministic per-seed conversation bridge-profile/session isolation for the run (without runtime patch-unit changes)

Example:

```bash
./run-shelley-managed-s4-recall-validation.sh \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --port 8922
```

Note:

- this first runner is an evidence-gathering harness, not a final product-memory verdict
- report should be reviewed manually; provisional outcome is intentionally heuristic

### Latest S4 runner checkpoint (first automated pass)

Executed:

```bash
./run-shelley-managed-s4-recall-validation.sh \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --port 8922
```

Report:

- `state/s4-recall-validation-last.json`
- DB: `/tmp/shelley-s4-recall-8922-1774217551.db`

Observed in this pass:

- all three seeded Shelley conversations mapped to the same remote Stavrobot conversation id (`conv_1`) under current local test profile behavior
- probe answers repeatedly referenced prior run tokens rather than current seeded tokens
- provisional heuristic outcome: `S4B` (low-confidence automation signal; manual review still required)

Interpretation note:

- this result is useful as baseline evidence that current profile/session behavior likely needs stricter conversation isolation controls before treating S4 outcomes as product-memory truth
- use `--require-remote-isolation` for the stricter S4 lane once profile/session behavior is expected to preserve distinct remote conversation IDs

### Strict S4 checkpoint (deterministic remote-isolation profile/session mode)

Executed:

```bash
./run-shelley-managed-s4-recall-validation.sh \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json \
  --port 8925 \
  --require-remote-isolation \
  --remote-isolation-profile-session
```

Report:

- `state/s4-recall-validation-last.json`
- DB: `/tmp/shelley-s4-recall-8925-1774223781.db`

Observed in this strict lane pass:

- strict remote isolation check now passes deterministically (`metadata.remote_isolation_ok = true`)
- seeded conversations used deterministic per-seed bridge profiles:
  - `local-default-s4-iso-a`
  - `local-default-s4-iso-b`
  - `local-default-s4-iso-c`
- remote IDs are now isolated by deterministic prefixed namespace in the run profile-session wrappers:
  - `s4iso-a:conv_1`
  - `s4iso-b:conv_1`
  - `s4iso-c:conv_1`

Interpretation note:

- this is a higher-confidence checkpoint for S4 lane integrity because it prevents false-positive “cross-conversation” conclusions caused by shared remote session identity
- it does **not** by itself improve model recall quality; it improves evidence hygiene by enforcing deterministic per-conversation remote identity isolation in the validation harness

## S4 strict runtime-contract lane (new)

A required-runtime contract test now exists for the strict S4 remote-isolation lane:

- `tests/test-s4-recall-validation-runtime-contract.sh`

Behavior mirrors the existing managed runtime contract tests:

- default mode is skip-safe when managed runtime prerequisites are absent
- `REQUIRE_PATCHED_MANAGED_RUNTIME=1` switches to fail-on-missing-prereqs behavior
- strict S4 runner now logs actionable HTTP/response/server-log diagnostics when create/chat API calls fail (instead of surfacing opaque downstream JSON parse errors)

What it asserts in the runnable lane:

- strict S4 run succeeds with:
  - `--require-remote-isolation`
  - `--remote-isolation-profile-session`
- report metadata confirms:
  - `require_remote_isolation = true`
  - `remote_isolation_profile_session = true`
  - `remote_isolation_ok = true`
- deterministic per-seed profile naming and remote-ID prefix isolation are present in metadata

## Aggregate managed memory-suitability gate (new)

A single deterministic helper now runs the three required-runtime contract lanes that matter for current memory-suitability evidence hygiene:

- raw-media runtime contract
- S2 narrow-fidelity runtime contract
- strict S4 remote-isolation runtime contract

Helper:

- `./run-shelley-managed-memory-suitability-gate.sh`

Recommended release/required-runtime invocation:

```bash
./run-shelley-managed-memory-suitability-gate.sh \
  --required-runtime \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json
```

This does not replace manual report review, but it gives a clean deterministic pre-checkpoint gate for the current S2+S4 evidence stack.

### Latest aggregate gate checkpoint

Executed successfully:

```bash
./run-shelley-managed-memory-suitability-gate.sh \
  --required-runtime \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json
```

Result:

- passed all three contract lanes in sequence:
  - `test-shelley-managed-smoke-raw-media-runtime-contract.sh`
  - `test-shelley-managed-smoke-s2-narrow-fidelity-contract.sh`
  - `test-s4-recall-validation-runtime-contract.sh`

## Installer/refresh wiring for aggregate memory-suitability gate (new)

The aggregate gate is now available directly via managed refresh wrappers:

- installer flag:
  - `--memory-suitability-gate-shelley-profile`
- refresh helper flag:
  - `--smoke-memory-suitability-gate-profile`

Behavior:

- runs `run-shelley-managed-memory-suitability-gate.sh --required-runtime` after managed rebuild
- preserves profile exclusivity rules with existing strict raw-media and S2 narrow-fidelity proof profiles
- rejects explicit smoke expectation/fixture flags in this profile mode to keep the lane deterministic

### Strict S4 isolation runner resilience tuning (new)

For environments where upstream/model latency is bursty, strict isolation mode now supports explicit per-seed bridge timeout/retry tuning:

- `--isolation-bridge-request-timeout SEC` (default `85`)
- `--isolation-bridge-retries COUNT` (default `1`)
- `--isolation-bridge-retry-delay SEC` (default `2`)

These flags only affect the deterministic per-seed isolation profiles created by `--remote-isolation-profile-session`; they do not mutate baseline profile-state files.

## Context-overflow resilience hardening (new)

Recent failures in required-runtime lanes were traced to upstream Stavrobot context-overflow errors surfacing as opaque bridge parse failures.

Hardening now in place:

- bridge-level soft-fail mode via `STAVROBOT_BRIDGE_CONTEXT_OVERFLOW_SOFTFAIL=1`
  - when overflow is detected from client stderr, bridge emits deterministic JSON with `raw.bridge_softfail = "context_overflow"` instead of exiting with non-JSON output
- strict S4 isolation wrappers force soft-fail mode and still namespace remote IDs, allowing deterministic isolation metadata even when turns fail due to context pressure
- strict S4 wrapper fallback now emits deterministic JSON for malformed/non-JSON bridge output, including stderr/stdout snippets
- fixture smoke/contract lanes short-circuit remote client/session calls in fixture mode, avoiding unrelated live-backend drift during deterministic fixture proofs

This keeps required-runtime gate behavior stable and diagnosable even under upstream context pressure.

### CI artifact capture (new)

Required-runtime CI lane now uploads artifacts on both pass/fail via:

- `ci/collect-memory-suitability-artifacts.sh`

Captured bundle includes (when present):

- `s4-server.log`
- `s4-runtime-contract.json`
- `s4-last-report.json`
- `diagnostics.txt` (docker/listener/runtime snapshot)
- `manifest.txt`

This provides direct postmortem data in CI UI without rerunning lanes interactively.

### S4 softfail policy mode (new)

Required-runtime gate entrypoints now support explicit S4 softfail policy control:

- `--s4-softfail-policy allow` (default): tolerate S4 context-overflow softfail evidence while keeping diagnostics
- `--s4-softfail-policy strict`: fail lane if S4 report contains context-overflow softfail evidence

Local required-runtime checkpoint flow should use `strict` policy to make context-pressure regressions explicit.

### CI checkpoint note helper (new)

To standardize first/ongoing strict-lane checkpoint recording, use:

```bash
./ci/render-memory-suitability-checkpoint-note.sh \
  --artifact-dir ./ci-artifacts \
  --run-ref <LOCAL_RUN_REF> \
  --output ./ci-artifacts/checkpoint-note.md
```

This renders a compact markdown block containing run URL, diagnostics timestamp, artifact manifest, and strict-policy reminder.

### CI checkpoint ledger + summary helpers (new)

To retain run history/trend signal across strict-lane executions, preferred one-step recorder:

```bash
./ci/record-memory-suitability-checkpoint.sh \
  --artifact-dir ./ci-artifacts \
  --run-ref <LOCAL_RUN_REF> \
  --outcome <pass|fail> \
  --policy strict \
  --s4-softfail-evidence <yes|no|unknown>
```

Equivalent split-mode commands (manual control):

```bash
./ci/append-memory-suitability-checkpoint-ledger.sh \
  --ledger-path ./docs/checkpoints/memory-suitability-required-runtime-ledger.json \
  --run-ref <LOCAL_RUN_REF> \
  --policy strict \
  --outcome <pass|fail> \
  --s4-softfail-evidence <yes|no|unknown> \
  --artifact-dir ./ci-artifacts \
  --artifact-ref memory-suitability-required-runtime-artifacts \
  --note-path ./ci-artifacts/checkpoint-note.md

./ci/render-memory-suitability-ledger-summary.sh \
  --ledger-path ./docs/checkpoints/memory-suitability-required-runtime-ledger.json \
  --last 10 \
  > ./docs/checkpoints/memory-suitability-required-runtime-summary.md
```

This keeps an append-only machine-readable index plus a compact human summary table for recent runs.

Ledger behavior note:
- duplicate protection is enabled by default on `run_ref + artifact_ref`; append helper rejects accidental double-writes unless `--allow-duplicate` is explicitly set.

### Local one-command checkpoint runner (new)

Preferred local operational command for this lane:

```bash
./ci/run-memory-suitability-local-checkpoint.sh --policy strict
```

This runs preflight + required-runtime gate + artifact collection + checkpoint recording (note/ledger/summary) in sequence and sets outcome/softfail evidence automatically from run artifacts.

### Optional local scheduling via systemd timer (new)

For unattended local cadence (without GitHub Actions), install/update timer units:

```bash
./ci/install-memory-suitability-local-checkpoint-timer.sh
```

Defaults:
- service: `memory-suitability-local-checkpoint.service`
- timer: `memory-suitability-local-checkpoint.timer`
- schedule: daily `06:17 UTC`

Override schedule with `--on-calendar`, e.g. `--on-calendar 'hourly'`.
