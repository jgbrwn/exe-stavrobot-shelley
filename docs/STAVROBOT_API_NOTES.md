# Stavrobot API notes for Shelley follow-up

## Current usable API surface

### Chat

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

### Plugin settings endpoints already used by installer

- `GET /api/settings/plugins/list`
- `POST /api/settings/plugins/install`
- `POST /api/settings/plugins/configure`
- detail/config helper endpoints also exist

## Missing pieces for a stronger Shelley integration

These are not blockers for the MVP adapter, but they are the likely next asks.

1. Stable conversation/session identifiers
2. Read-only conversation history endpoint
3. Read-only event/trace endpoint
4. Dedicated health/status endpoint
5. Possibly a cleaner machine API namespace separated from browser settings UI routes

## Recommended order

1. Keep using the local adapter now.
2. Validate actual Shelley workflows against `/chat`.
3. Only then propose upstream API additions based on concrete pain points.

## Concrete proposal

A concrete additive upstream proposal now lives in:

- `docs/STAVROBOT_UPSTREAM_API_PROPOSAL.md`
