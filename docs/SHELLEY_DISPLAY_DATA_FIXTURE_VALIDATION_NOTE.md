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
