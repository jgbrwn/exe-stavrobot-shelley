# Shelley S2 structured bridge target

## Purpose

Define the smallest useful S2 extension for the canonical Shelley-facing bridge so Shelley can improve fidelity without abandoning the single-bridge contract or regressing the current S1 text-first path.

This document is intentionally narrow.

It does not try to solve every future rich-content case.
It defines the first structured-output target that is worth implementing next.

## Goals

1. keep `shelley-stavrobot-bridge.sh` as the only Shelley-facing runtime contract
2. preserve today's S1 response-text behavior as a fallback
3. improve Shelley-native rendering fidelity for the first high-value cases
4. avoid freezing the Shelley runtime into a permanent plain-text tunnel
5. preserve upstream Shelley mobile/responsive behavior by adapting into existing Shelley surfaces

## Non-goals

This S2 target does not require:

- a new parallel Stavrobot-specific thread renderer
- full arbitrary multimodal parity on the first increment
- remote history/event reconciliation on every turn
- cross-conversation retrieval/memory behavior
- Shelley-native backend model-control UI

## Current S1 baseline

Today the canonical bridge already gives Shelley a stable minimum envelope:

- response text
- remote `conversation_id`
- remote `message_id`
- machine-readable JSON as the default bridge output
- text-only extraction via `--extract response` for human/operator use

That means S2 should extend the structured payload, not replace it.

## Recommended first-class S2 adaptation targets

The first S2 increment should target only these three areas:

1. **markdown-preserving assistant text**
2. **tool/event summary display**
3. **image/media references when the bridge can supply them cleanly**

Anything else should continue to fall back safely.

## Recommended bridge result shape

The bridge should keep returning the current top-level fields and may add a narrow optional structured section.

Minimum recommended shape:

```json
{
  "ok": true,
  "response": "Here is the assistant reply in markdown.",
  "conversation_id": "conv_123",
  "message_id": "msg_456",
  "content": [
    {
      "kind": "markdown",
      "text": "Here is the assistant reply in markdown."
    }
  ],
  "display": {
    "tool_summary": [
      {
        "tool": "browser",
        "status": "ok",
        "title": "Fetched page title"
      }
    ]
  },
  "artifacts": [
    {
      "kind": "image",
      "url": "https://example.test/image.png",
      "title": "Screenshot"
    }
  ],
  "raw": {
    "provider_payload": {}
  }
}
```

## Field-by-field intent

### Existing fields to preserve

- `ok`
- `response`
- `conversation_id`
- `message_id`

These remain the baseline compatibility path.

### New optional `content`

Purpose:

- give Shelley an ordered content-oriented result list that can map into native message/content structures

First supported kinds:

- `markdown`
- `text`
- `image_ref`

Recommended minimal shapes:

```json
{ "kind": "markdown", "text": "..." }
{ "kind": "text", "text": "..." }
{ "kind": "image_ref", "url": "...", "title": "optional" }
```

### New optional `display`

Purpose:

- carry compact display-oriented metadata that fits Shelley's existing trace/display affordances without forcing raw debug JSON into the main message body

First supported subfield:

- `tool_summary`

Recommended shape:

```json
{
  "tool_summary": [
    {
      "tool": "browser",
      "status": "ok",
      "title": "Fetched page title"
    }
  ]
}
```

This is intentionally summary-level, not a full event log.

### New optional `artifacts`

Purpose:

- carry references to richer outputs that Shelley may later map more directly

First supported kind:

- `image`

Recommended minimal shape:

```json
{
  "kind": "image",
  "url": "https://example.test/image.png",
  "title": "Screenshot"
}
```

### Optional `raw`

Purpose:

- preserve room for future debugging or later adaptation without forcing S2 mapping logic to depend on ad hoc provider text parsing

Rule:

- Shelley should not render `raw` directly in the normal conversation flow
- `raw` exists as an adaptation/debug aid, not as the end-user UI payload

## Adaptation rules inside Shelley

## Rule 1: text fallback always works

If `content` is absent or unsupported, Shelley should still render using `response`.

This is the most important safety rule.

## Rule 2: prefer native Shelley content surfaces

If `content` is present and supported:

- map `markdown` into Shelley's normal markdown-friendly assistant content
- map `text` into Shelley text content
- map `image_ref` or `artifacts.image` into Shelley-native media/content surfaces when available
- until a stable native media-content mapping is chosen, it is acceptable to preserve compact image/media references in display-oriented metadata rather than pretending they are already a first-class assistant block

## Rule 3: keep tool summaries compact

Tool or event summaries should:

- appear through existing display/trace affordances where possible
- remain compact in the main thread view
- avoid turning the thread into a raw event log

## Rule 4: unsupported rich fields degrade explicitly

If Shelley encounters an unsupported `content.kind` or artifact kind:

- do not fail the whole turn
- do not silently discard all useful output
- fall back to `response`
- optionally retain unsupported data in internal/raw payload for later debugging

## Recommended first implementation cut

The first S2 implementation should support only:

1. `content.kind = markdown`
2. `display.tool_summary`
3. one simple image/media reference shape

Current bridge-side progress note:

- compact `tool_summary` can now be enriched from events endpoint output when chat payloads are text-only
- a narrow image/media-reference extraction path now also exists for obvious image URLs (payload fields, response markdown/text URLs, and recent event-summary URLs), emitted as `artifacts.kind = image`

Why this scope is still right after inspecting upstream Shelley more closely:

- markdown/text already map cleanly into normal Shelley assistant content
- compact tool summaries fit Shelley's existing display-oriented metadata approach without needing a separate Stavrobot renderer
- Shelley clearly has rich image/screenshot handling, but today that richness is strongest through tool-result/media patterns rather than a generic arbitrary rich assistant block
- Shelley does have strong HTML/embed presentation via the sandboxed `output_iframe` tool path, but not yet an obvious generic assistant-HTML content primitive that Stavrobot should target directly on the first cut
- audio/video may also be possible later, but they should follow a concrete Shelley-native shape rather than arriving first as opaque raw payload attachments

That is enough to improve fidelity meaningfully without overexpanding the patch.

## Things to defer even within S2

Defer these until after the first S2 cut is proven useful:

- full event timelines in the main thread UI
- arbitrary HTML rendering
- large nested tool payload rendering
- generalized file/artifact download UX
- rich interactive controls beyond native Shelley components

## Bridge-side contract discipline

The canonical bridge should remain the only Shelley-facing executable contract.

That means:

- Shelley should not shell out directly to lower-level client wrappers for normal turn rendering
- lower-level wrappers remain implementation details
- bridge JSON should be stable enough that Shelley mapping logic does not depend on fragile string scraping

## Mobile / responsive preservation rule

S2 must preserve upstream Shelley's strong mobile/responsive behavior.

Implications:

- use existing Shelley content/message components where possible
- keep tool summaries short and collapsible if needed
- do not introduce a wide Stavrobot-specific side panel as a requirement for understanding a turn
- keep media handling aligned with Shelley's existing responsive content behavior

## Validation checklist for this target

A minimal S2 validation pass should verify:

1. plain markdown response still renders cleanly
2. absence of `content` still falls back to `response`
3. `content.kind = markdown` renders through Shelley-native assistant content
4. `display.tool_summary` appears legibly without overwhelming the thread
5. image/media reference mapping uses Shelley-native content handling when available
6. unsupported `content.kind` does not break the turn
7. ordinary non-Stavrobot Shelley conversations remain unchanged
8. narrow/mobile layouts remain usable
9. if compact display metadata is intentionally preserved only in message metadata at first, docs/tests should say so explicitly rather than implying it already renders through Shelley's `display_data` path

## Recommended next implementation artifact after this document

The next code-facing step should be one of:

1. extend `shelley-stavrobot-bridge.sh` with a documented optional richer payload mode while preserving current fields
2. or refine the managed Shelley runtime-unit result/adaptation types so they explicitly accept:
   - `content`
   - `display`
   - `artifacts`
   - `raw`

The preferred sequence is:

- lock the contract first
- then adapt the Shelley runtime boundary
- then add only the first narrow rendering improvements
