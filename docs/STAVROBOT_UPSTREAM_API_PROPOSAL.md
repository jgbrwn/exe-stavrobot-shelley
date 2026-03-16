# Proposed upstream Stavrobot API additions for Shelley

## Goal

Add the smallest machine-oriented API surface that makes Shelley a materially better frontend for Stavrobot without redesigning the whole app.

## Design principles

1. Keep existing `/chat` working unchanged.
2. Add new endpoints instead of breaking web UI routes.
3. Prefer read-only introspection first.
4. Reuse existing Basic Auth model initially.
5. Keep payloads simple JSON.

## Proposed namespace

Use a dedicated namespace for machine clients:

- `/api/client/chat`
- `/api/client/conversations`
- `/api/client/events`
- `/api/client/health`

This avoids coupling Shelley to web-settings endpoints and leaves room for future clients.

## 1) Session-aware chat endpoint

### Endpoint

- `POST /api/client/chat`

### Request

```json
{
  "message": "Summarize the deployment status",
  "conversation_id": "optional-stable-id",
  "source": "shelley",
  "sender": "operator"
}
```

### Response

```json
{
  "response": "Current deployment looks healthy...",
  "conversation_id": "conv_123",
  "message_id": "msg_456"
}
```

### Why

Current `/chat` returns only `response`. Shelley needs a stable handle to continue or inspect the same conversation.

## 2) Conversation listing

### Endpoint

- `GET /api/client/conversations`

### Response

```json
{
  "conversations": [
    {
      "conversation_id": "conv_123",
      "title": "Deployment troubleshooting",
      "updated_at": "2025-03-16T18:00:00Z"
    }
  ]
}
```

### Why

Shelley needs a lightweight way to discover recent conversations without scraping DBs or HTML.

## 3) Conversation history

### Endpoint

- `GET /api/client/conversations/:conversation_id/messages`

### Response

```json
{
  "conversation_id": "conv_123",
  "messages": [
    {
      "message_id": "msg_1",
      "role": "user",
      "text": "Check app health",
      "created_at": "2025-03-16T17:58:00Z"
    },
    {
      "message_id": "msg_2",
      "role": "assistant",
      "text": "The app is healthy.",
      "created_at": "2025-03-16T17:58:02Z"
    }
  ]
}
```

### Why

This is the minimum useful history surface for Shelley. It should be read-only at first.

## 4) Event or trace feed

### Endpoint

- `GET /api/client/conversations/:conversation_id/events`

### Response

```json
{
  "conversation_id": "conv_123",
  "events": [
    {
      "event_id": "evt_1",
      "type": "tool_call",
      "name": "run_plugin_tool",
      "status": "completed",
      "created_at": "2025-03-16T17:58:01Z",
      "summary": "Executed weather plugin"
    }
  ]
}
```

### Why

Shelley does not need every internal detail immediately, but some event visibility would make the frontend much more legible.

## 5) Health endpoint

### Endpoint

- `GET /api/client/health`

### Response

```json
{
  "ok": true,
  "version": "optional git sha or app version",
  "provider": "anthropic",
  "model": "claude-sonnet-4-20250514",
  "plugins_endpoint": true
}
```

### Why

The installer currently infers health via authenticated page checks and plugin endpoint checks. A real client endpoint would be cleaner.

## Suggested implementation order

Status so far from upstream spike work:

1. `GET /api/client/health` has been prototyped and validated.
2. `POST /api/client/chat` has been prototyped and validated with a real LLM-backed response.
3. `POST /api/client/chat` has also been spiked with real `conversation_id` support.
4. `GET /api/client/conversations` has been spiked.
5. `GET /api/client/conversations/:conversation_id/messages` has been spiked.
6. a live runtime pass against the rebuilt stack validated health, first chat, conversation listing, message history, and a second chat using the same `conversation_id`.
7. `GET /api/client/conversations/:conversation_id/events` has now also been spiked and live-validated as a read-only tool-event feed.

Recommended next implementation steps:

8. add real `message_id` in `POST /api/client/chat` if a client needs it

## Backward-compatibility stance

- Keep `/chat` unchanged.
- Keep current web UI endpoints unchanged.
- Treat `/api/client/*` as additive.

## Why this is enough for now

This gives Shelley:
- a stable chat target
- enough history to render useful context
- enough status to validate connectivity
- a path to richer UX later without forcing a full API redesign now
