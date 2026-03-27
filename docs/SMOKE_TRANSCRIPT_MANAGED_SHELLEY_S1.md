# End-to-end smoke transcript (managed Shelley S1 + Stavrobot mode)

Date: 2026-03-27 (local VM)

Purpose: provide one concrete operator transcript proving the integrated managed flow can run end-to-end, including Stavrobot mode turn persistence and display-data/media-ref persistence checks.

## Command

```bash
./smoke-test-shelley-managed-s1.sh \
  --shelley-dir /opt/shelley \
  --profile-state-path /var/lib/stavrobot-installer/shelley-bridge-profiles.json \
  --bridge-profile local-default \
  --port 8765 \
  --db-path /tmp/shelley-stavrobot-managed-test-transcript.db \
  --tmux-session shelley-managed-s1-smoke-transcript \
  --bridge-fixture s2_markdown_media_refs \
  --expect-display-data \
  --require-display-hints \
  --expect-media-refs \
  --require-media-refs
```

## Script output (verbatim)

```text
[info] Starting isolated Shelley test server on port 8765
[info] Waiting for Shelley server readiness
[info] Creating normal control conversation
[info] Creating Stavrobot-mode conversation
[info] Sending Stavrobot continuation turn
[info] Checking persisted conversation metadata
[info] Checking persisted display_data on Stavrobot assistant messages
[info] Checking persisted display_data.media_refs on Stavrobot assistant messages
[info] Managed Shelley S1 smoke test passed
[info] Normal conversation: cDUPY4L
[info] Stavrobot conversation: cF55REJ
[info] DB path: /tmp/shelley-stavrobot-managed-test-transcript.db
[info] Server log: /tmp/shelley-managed-s1-smoke.log
```

## Persisted conversation-options evidence

Query:

```bash
sqlite3 -json /tmp/shelley-stavrobot-managed-test-transcript.db \
  "select conversation_id, conversation_options from conversations where conversation_id in ('cDUPY4L','cF55REJ');"
```

Result:

```json
[
  {
    "conversation_id": "cDUPY4L",
    "conversation_options": "{}"
  },
  {
    "conversation_id": "cF55REJ",
    "conversation_options": "{\"type\":\"stavrobot\",\"stavrobot\":{\"enabled\":true,\"conversation_id\":\"conv_fixture\",\"last_message_id\":\"msg_fixture\",\"bridge_profile\":\"local-default\"}}"
  }
]
```

## Persisted assistant display-data/media-ref evidence

Query:

```bash
sqlite3 -json /tmp/shelley-stavrobot-managed-test-transcript.db \
  "select sequence_id, type, substr(llm_data,1,200) as llm_snip, substr(display_data,1,220) as display_snip from messages where conversation_id='cF55REJ' order by sequence_id;"
```

Result snippet highlights:

- agent turns include markdown-first content beginning with `## S2 fixture heading`
- `display_data` contains `media_refs` including image references and artifact image references

This transcript is fixture-backed (`s2_markdown_media_refs`) for deterministic runtime/output checks.
