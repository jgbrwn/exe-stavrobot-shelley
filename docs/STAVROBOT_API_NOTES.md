# Stavrobot API notes for Shelley follow-up

## Current validated API surface

### Existing upstream chat

- Endpoint: `POST /chat`
- Auth: HTTP Basic Auth using Stavrobot password
- Request fields observed:
  - `message` (string, required unless attachments/files used)
  - `source` (string, optional)
  - `sender` (string, optional)
  - `attachments` (optional)
  - `files` (optional)
- Response:
  - JSON containing `response`

This remains the current Shelley MVP integration path via `chat-with-stavrobot.sh`.

### Additive upstream client endpoints validated in test clone

A real upstream Stavrobot test clone was used to spike additive machine-oriented endpoints under `/api/client/*`.

Validated endpoints/results so far:

- `GET /api/client/health`
- `POST /api/client/chat`
- `GET /api/client/conversations`
- `GET /api/client/conversations/:conversation_id/messages`
- `GET /api/client/conversations/:conversation_id/events`

Observed behavior from the spike:

- `GET /api/client/health` returned machine-readable provider/model/config status.
- `POST /api/client/chat` worked end-to-end and returned a real LLM-backed response.
- `POST /api/client/chat` now returns a real stable `conversation_id` in the spike implementation.
- Omitting `conversation_id` routes to the main conversation (`conv_1`).
- Supplying `conversation_id` continues an existing conversation.
- `GET /api/client/conversations` returns machine-readable conversation summaries.
- `GET /api/client/conversations/:conversation_id/messages` returns machine-readable history.
- `GET /api/client/conversations/:conversation_id/events` returns machine-readable tool-call and tool-result events derived from stored messages.
- `POST /api/client/chat` now returns a real chat `message_id` in the spike implementation.

A follow-up live runtime validation pass against the rebuilt local stack also confirmed:

- `GET /api/client/health` returned `ok: true` with provider `openrouter` and model `z-ai/glm-4.5-air:free`.
- the first `POST /api/client/chat` returned `conversation_id: "conv_1"`.
- `GET /api/client/conversations` included that same `conversation_id`.
- `GET /api/client/conversations/conv_1/messages` returned real message history with `message_id` values such as `msg_35` and `msg_36`.
- a second `POST /api/client/chat` reusing `conversation_id: "conv_1"` appended additional history as expected.
- `GET /api/client/conversations/conv_1/events` returned machine-readable tool events including `tool_call` and `tool_result` entries with names such as `send_signal_message` and `manage_interlocutors`.
- a later live validation pass confirmed `POST /api/client/chat` returned a real assistant `message_id` such as `msg_42`, and that same ID matched the persisted assistant message returned by the history endpoint.

One operational nuance from live validation: after rebuilding the upstream test stack, the app container had to be force-recreated before the running service picked up the newly built conversation-route code. The real installer in this repo already does this correctly via `docker compose up -d --build --force-recreate`.

### OpenRouter compatibility finding

A real live test against Stavrobot with provider `openrouter` succeeded without any Stavrobot patching.

Important result:

- Stavrobot already supports OpenRouter with current provider/model handling.
- The earlier failed OpenRouter attempt was a model/account/policy issue, not proof of missing Stavrobot support.
- A successful live response was confirmed with model `z-ai/glm-4.5-air:free`.

Because the OpenRouter key used for testing was pasted interactively during prior work, it should be treated as exposed and rotated later.

### Plugin settings endpoints already used by installer

- `GET /api/settings/plugins/list`
- `POST /api/settings/plugins/install`
- `POST /api/settings/plugins/configure`
- detail/config helper endpoints also exist

## Main-repo local consumption status

The main repo now consumes this validated direction locally in two ways:

1. `chat-with-stavrobot.sh` remains the thin lowest-risk adapter around existing authenticated `POST /chat`.
2. `client-stavrobot.sh` now provides a local machine-oriented wrapper for:
   - `GET /api/client/health`
   - `POST /api/client/chat`
   - `GET /api/client/conversations`
   - `GET /api/client/conversations/:conversation_id/messages`
   - `GET /api/client/conversations/:conversation_id/events`
3. `smoke-test-stavrobot-client.sh` exercises health, chat, listing, history, and events together against a live stack.

## What is still missing for stronger Shelley integration

The next missing piece after the successful session/history/events/message-id spike is now narrower.

1. Any further client ergonomics discovered during Shelley integration
2. Possibly a higher-level Shelley-side state wrapper if conversation reuse/pinning becomes a frequent workflow

## Recommended order now

1. Keep using the local adapter in this repo for the Shelley MVP.
2. Preserve the additive upstream `/api/client/*` direction.
3. Treat conversation IDs, conversation listing, and conversation history as validated upstream direction.
4. Treat the read-only events endpoint as validated upstream direction.
5. Treat real chat `message_id` support as validated upstream direction too.

## Concrete proposal

A concrete additive upstream proposal lives in:

- `docs/STAVROBOT_UPSTREAM_API_PROPOSAL.md`
