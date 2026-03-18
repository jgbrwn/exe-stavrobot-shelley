# Shelley/Stavrobot raw media phase 1 contract (bridge-first)

## Goal

Add a **bounded, explicit** raw-media path without breaking the current URL-based media-ref behavior.

This phase is bridge-only contract work so runtime adaptation can consume it safely later.

## Existing behavior to preserve

- URL/image-reference extraction remains supported and unchanged in spirit (`artifacts.kind = image` + `url`).
- Text fallback remains mandatory (`response` + markdown `content`).
- Unsupported/unknown media must never fail the turn.

## New phase-1 raw-media shape

Bridge may emit image artifacts with inline base64 payload:

```json
{
  "kind": "image",
  "mime_type": "image/png",
  "transport": "raw_inline_base64",
  "byte_length": 12345,
  "data_base64": "...",
  "title": "optional"
}
```

## Acceptance criteria (bridge)

1. Only image MIME types are accepted in phase 1:
   - `image/png`, `image/jpeg`, `image/gif`, `image/webp`
2. Input raw media fields are narrowly recognized from provider payloads (artifact/media lists and select top-level base64 fields).
3. Payload is base64-decoded and size-checked before emission.
4. Oversize/invalid/unsupported raw media is skipped; bridge emits compact note(s) under `display.media_notes`.
5. Deduplication is applied for raw payloads (content-hash based).

## Limits and controls

Environment flags on `shelley-stavrobot-bridge.sh`:

- `STAVROBOT_BRIDGE_RAW_MEDIA_ENABLED` (default `1`, allowed: `0|1`)
- `STAVROBOT_BRIDGE_RAW_MEDIA_MAX_BYTES` (default `262144` = 256 KiB)

These bound risk and allow operators to hard-disable raw-media extraction without changing code.

## Runtime adaptation impact (next step)

Current managed Shelley runtime already persists `display_data.media_refs` for URL paths.

Next runtime step should consume `artifacts.image` entries where `transport=raw_inline_base64` and map into Shelley-native persisted media structures with equivalent bounds/fallbacks.

Until then, phase-1 bridge output is forward-compatible and non-breaking.

## Validation

Structured bridge tests now cover:

- acceptance/preservation of a small inline raw image artifact
- rejection of oversized raw image with `display.media_notes` evidence
- continued URL-based artifact extraction behavior
