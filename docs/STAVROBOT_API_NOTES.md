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

Validated endpoints/results:

- `GET /api/client/health`
- `POST /api/client/chat`

Observed behavior from the spike:

- `GET /api/client/health` returned machine-readable provider/model/config status.
- `POST /api/client/chat` worked end-to-end and returned a real LLM-backed response.
- The current client chat spike still returned placeholder metadata:
  - `conversation_id: null`
  - `message_id: null`

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

## What is still missing for stronger Shelley integration

These are no longer speculative in the same way. After the successful `/api/client/chat` live test, these are the next justified upstream steps.

1. Real `conversation_id` support in `POST /api/client/chat`
2. `GET /api/client/conversations`
3. `GET /api/client/conversations/:conversation_id/messages`
4. Read-only event/trace endpoint later if needed

## Recommended order now

1. Keep using the local adapter in this repo for the Shelley MVP.
2. Preserve the additive upstream `/api/client/*` direction.
3. Implement real `conversation_id` support upstream next.
4. Then add conversation listing and message history endpoints.
5. Leave event/trace work for a later increment.

## Concrete proposal

A concrete additive upstream proposal lives in:

- `docs/STAVROBOT_UPSTREAM_API_PROPOSAL.md`
