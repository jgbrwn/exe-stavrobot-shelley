# Shelley ↔ Stavrobot MVP plan

## Goal

Define the smallest useful Shelley integration path for Stavrobot on exe.dev without requiring immediate upstream Stavrobot changes.

## Constraints discovered so far

1. Stavrobot already exposes a stable-enough authenticated HTTP chat endpoint at `POST /chat`.
2. That endpoint accepts:
   - `message`
   - optional `source`
   - optional `sender`
   - optional attachments/files
3. It returns JSON containing `response`.
4. Stavrobot also exposes authenticated settings/plugin endpoints that the installer already uses.
5. There is currently no dedicated conversation-history/events API designed for Shelley.
6. There is no explicit "Shelley mode" in Stavrobot today.

## Recommended MVP

Phase 2 Shelley work should start with a thin adapter instead of upstream modifications.

### MVP shape

Add a local helper entrypoint in this repo:
- `chat-with-stavrobot.sh`

Purpose:
- act as the narrow compatibility layer between Shelley and a running Stavrobot instance
- read Stavrobot auth from `config.toml`
- send a prompt to `/chat`
- print the assistant response to stdout

### Why this is the right first move

- It uses existing Stavrobot behavior.
- It avoids speculative upstream API design.
- It gives Shelley a concrete integration surface immediately.
- It is easy to test locally and easy to replace later.

## Proposed Shelley integration flow

1. Operator deploys Stavrobot with `install-stavrobot.sh`.
2. Operator validates email worker/manual integrations as needed.
3. Shelley invokes `chat-with-stavrobot.sh` with:
   - `--stavrobot-dir /path/to/stavrobot`
   - `--message ...`
4. The adapter posts to Stavrobot `/chat` using Basic Auth from config.
5. The adapter prints only the assistant response by default.

## MVP limitations

- No streaming output yet.
- No first-class conversation/session controls beyond what Stavrobot already does internally.
- No history sync into Shelley.
- No structured tool/event trace surfaced back to Shelley.
- No attachment bridging beyond raw `/chat` support.

## Likely next upstream asks after MVP

If Shelley proves valuable as a frontend, the next likely Stavrobot API additions would be:

1. Conversation/session identifiers for `/chat`
2. Read-only conversation/history endpoint
3. Read-only events or traces endpoint
4. Health/status endpoint richer than basic auth page checks
5. Maybe a stable machine-oriented API namespace distinct from the current web UI endpoints

## Decision

Start Shelley integration with the adapter script first.
Do not block on upstream Stavrobot changes.

## Adapter hardening notes

The first adapter hardening pass should prefer local improvements before upstream changes:

- configurable base URL
- configurable connect/request timeouts
- retry behavior for transport failures
- raw JSON debug mode
- stdin support for piping prompts from other tools

These are now implemented in `chat-with-stavrobot.sh`.

## Next planning artifact

The proposed additive upstream API surface is documented in:

- `docs/STAVROBOT_UPSTREAM_API_PROPOSAL.md`
