# Shelley runtime adaptation contract for Stavrobot mode

## Purpose

Define the recommended runtime-side result and adaptation boundary for the managed Shelley patch surface after S1.

This document bridges the gap between:

- the existing S1 text-first `server/stavrobot.go` runtime shape
- the new `docs/SHELLEY_S2_STRUCTURED_BRIDGE_TARGET.md`
- the need to keep patch `0004` implementation-facing rather than permanently text-locked

## Why this exists

The repo already has two important conclusions:

1. `server/stavrobot.go` is the right long-term runtime/adaptation seam
2. that seam should not freeze the Shelley↔Stavrobot boundary into `ResponseText` only

What was still missing was a concrete contract for what the runtime layer should own versus what the bridge layer should own versus what the Shelley message-recording layer should own.

This document provides that contract.

## High-level boundary

Recommended layering:

1. **bridge execution layer**
   - invokes `shelley-stavrobot-bridge.sh`
   - parses bridge JSON
   - returns a runtime result shape that preserves both normalized fields and richer optional payload
2. **runtime adaptation layer**
   - normalizes bridge output into Shelley-oriented result fields
   - prepares content/display/artifact data for later message recording
3. **conversation turn orchestration layer**
   - records user message
   - updates remote mapping metadata
   - records assistant message/error state
   - notifies subscribers

This means:

- the bridge should not directly decide Shelley UI rendering
- handlers should not parse ad hoc bridge JSON themselves
- `ProcessStavrobotConversationTurn(...)` remains the place where Shelley-native recording decisions happen

## Recommended core runtime types

## 1. Raw bridge payload type

Recommended conceptual role:

- preserve the canonical bridge output as parsed data
- keep unknown future fields available without forcing immediate adaptation decisions

Conceptual shape:

```go
type StavrobotBridgePayload struct {
    OK             bool                   `json:"ok"`
    Response       string                 `json:"response"`
    ConversationID string                 `json:"conversation_id"`
    MessageID      string                 `json:"message_id"`
    Content        []StavrobotBridgeContent `json:"content,omitempty"`
    Display        *StavrobotBridgeDisplay  `json:"display,omitempty"`
    Artifacts      []StavrobotArtifact      `json:"artifacts,omitempty"`
    Raw            map[string]any           `json:"raw,omitempty"`
}
```

Notes:

- exact Go field names can change
- the important point is preserving parsed bridge structure, not only flattened response text

## 2. Bridge content type

Conceptual shape:

```go
type StavrobotBridgeContent struct {
    Kind  string `json:"kind"`
    Text  string `json:"text,omitempty"`
    URL   string `json:"url,omitempty"`
    Title string `json:"title,omitempty"`
}
```

Initial expected kinds:

- `markdown`
- `text`
- `image_ref`

## 3. Bridge display type

Conceptual shape:

```go
type StavrobotBridgeDisplay struct {
    ToolSummary []StavrobotToolSummary `json:"tool_summary,omitempty"`
}

type StavrobotToolSummary struct {
    Tool   string `json:"tool"`
    Status string `json:"status"`
    Title  string `json:"title,omitempty"`
}
```

This should stay summary-oriented in the first S2 increment.

## 4. Artifact type

Conceptual shape:

```go
type StavrobotArtifact struct {
    Kind  string `json:"kind"`
    URL   string `json:"url,omitempty"`
    Title string `json:"title,omitempty"`
}
```

Initial expected kind:

- `image`

## 5. Runtime result type

This is the key contract.

Recommended role:

- represent the fully parsed result of one Stavrobot turn as it moves from bridge execution toward Shelley recording

Conceptual shape:

```go
type StavrobotTurnResult struct {
    ResponseText      string
    ConversationID    string
    MessageID         string
    RawBridgePayload  *StavrobotBridgePayload

    AssistantContent  []llm.Content
    DisplayData       map[string]any
    UnsupportedKinds  []string
}
```

Important design intent:

- `ResponseText` remains the mandatory fallback field
- `RawBridgePayload` preserves future adaptation room
- `AssistantContent` is the normalized Shelley-oriented content output
- `DisplayData` carries compact Shelley-display-oriented metadata
- `UnsupportedKinds` helps degrade explicitly instead of silently flattening or dropping everything

## Ownership by function boundary

## `ExecuteStavrobotTurn(...)`

Should own:

- subprocess invocation
- bridge JSON parsing
- low-level payload validation
- initial normalization into `StavrobotTurnResult`

Should not own:

- direct UI rendering decisions
- conversation metadata persistence
- subscriber notification

Recommended output behavior:

- always populate `ResponseText` when a text fallback is available
- populate `RawBridgePayload` when parsing succeeds
- populate `AssistantContent` when bridge `content` can be normalized safely
- populate `DisplayData` only with compact, stable summary data
- record unsupported rich kinds in `UnsupportedKinds`
- in the current repo state, this means normalizing the canonical bridge fields that already exist in practice today: markdown-first/text `content`, compact `display.tool_summary`, and `raw`, while still degrading unsupported media/artifact kinds explicitly

## `ProcessStavrobotConversationTurn(...)`

Should own:

- choosing how `AssistantContent` and fallback text become recorded Shelley assistant messages
- deciding how much of `DisplayData` gets attached to recorded message metadata
- updating `conversation_id` and `last_message_id`
- user-visible error handling

Should not own:

- raw JSON string scraping from the bridge
- low-level subprocess argument assembly

## Concrete upstream Shelley capability notes

A quick direct review of current upstream Shelley shows a few important implementation constraints/opportunities for this contract:

- `llm.Content` today is richer than plain text, but its stable first-class content types are still centered on:
  - text
  - thinking / redacted thinking
  - tool_use
  - tool_result
- image-like binary payloads can already ride through Shelley content using `MediaType` + `Data`, and current UI rendering is strongest when those appear inside tool-result-oriented flows
- compact `display_data` rendering in the UI is currently driven primarily by tool-result `Display` extraction, not by arbitrary assistant-side rich blocks
- HTML/embed rendering exists in Shelley today through the `output_iframe` tool UI path, which is sandboxed and responsive, not through generic raw assistant HTML rendering
- there is not yet an obvious generic first-class assistant content block for arbitrary HTML/audio/video/embed payloads independent of tool-style rendering

Practical consequence:

- markdown/text adaptation is low-risk now
- compact tool-summary metadata is also low-risk now
- image/screenshot handling may become viable soon if the runtime later chooses a Shelley-native image/tool-result shape deliberately
- HTML/audio/video should stay deferred until the bridge supplies a stable shape and the runtime chooses a native Shelley-safe mapping path instead of dumping raw markup into ordinary assistant text

## Recommended normalization rules

## Rule 1: `ResponseText` stays mandatory

Even after S2 widening, the runtime layer should still preserve a simple text fallback.

If richer content adaptation fails, Shelley should still be able to record an assistant reply from `ResponseText`.

## Rule 2: only normalize a small supported set first

Initial normalization target:

- `markdown` → markdown-friendly `llm.Content`
- `text` → text content
- `image_ref` / simple image artifact → Shelley-native content only if a safe existing content form exists

Unsupported kinds:

- do not fail the whole turn
- add to `UnsupportedKinds`
- preserve `RawBridgePayload`
- fall back to `ResponseText`

## Rule 3: `DisplayData` stays compact

First S2 use should be summary-level only.

Examples:

- tool summary rows
- small trace/status summary
- compact adaptation flags

Avoid in the first increment:

- full raw event timelines
- huge nested tool payloads
- desktop-only side panels as a required rendering target

## Rule 4: raw payload is for adaptation/debugging, not direct UI

`RawBridgePayload` exists so future code can adapt richer data without re-parsing raw subprocess output.

It should not automatically be rendered into the user-visible thread.

## Recommended assistant-message recording contract

When `ProcessStavrobotConversationTurn(...)` records the assistant turn:

Preferred order:

1. if `AssistantContent` is supported and non-empty, record it
2. else record fallback text from `ResponseText`
3. attach compact message metadata including:
   - remote `conversation_id`
   - remote `message_id`
   - compact display/tool summary metadata when appropriate
4. never require the presence of rich fields for a turn to succeed

## Error-handling contract

If bridge execution or payload parsing fails:

- keep current S1 style of producing actionable Shelley-visible error behavior
- do not partially record corrupt rich-content state
- do not lose the ability to return a simple Stavrobot error message into the thread

If adaptation of rich fields fails but basic response text is usable:

- do not fail the turn
- record fallback text
- optionally log/debug-note unsupported adaptation details

## Suggested first code-facing widening steps

1. widen `StavrobotTurnResult` first
2. add parsed raw bridge payload retention
3. add optional normalized `AssistantContent`
4. add compact `DisplayData`
5. keep actual recording behavior conservative until bridge richer fields stabilize

This sequence keeps patch `0004` easy to review while aligning it with the S2 target.

## Compatibility with current S1 patch surface

This contract is intended to be backward-compatible with the current S1 text-first implementation mindset.

That means a valid S1-compatible `StavrobotTurnResult` may still look like:

```go
type StavrobotTurnResult struct {
    ResponseText      string
    ConversationID    string
    MessageID         string
    RawBridgePayload  *StavrobotBridgePayload
    AssistantContent  nil
    DisplayData       nil
    UnsupportedKinds  nil
}
```

So widening the type does not require immediate rich rendering support.

## Mobile / responsive preservation rule

This runtime contract should actively support the UI-preservation goal.

That means:

- prefer compact normalized data that existing Shelley surfaces can present well
- do not design the runtime result around a future custom Stavrobot dashboard
- keep rich additions compatible with ordinary thread rendering on narrow/mobile layouts

## Relation to patch 0004

This document should be read as the implementation-facing widening guidance for:

- `patches/shelley/series/0004-stavrobot-runtime-unit.patch`
- `patches/shelley/series/0004-stavrobot-runtime-unit.patch-plan.md`

Practical interpretation:

- patch `0004` can remain behaviorally S1 for now
- but its helper/result boundaries should be shaped so the S2 contract can land without undoing the runtime unit design

## Recommended next step after this contract

The next implementation-facing move should be either:

1. update the patch-0004 plan docs to reference this widened runtime contract explicitly
2. or apply a small doc-only refinement to the patch-series notes so future sessions know the preferred `StavrobotTurnResult` widening path before editing upstream Shelley code
