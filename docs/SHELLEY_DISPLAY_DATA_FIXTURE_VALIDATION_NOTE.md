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
