# Patch 0004: focused Stavrobot runtime integration unit

## Goal

Create the cleaned Shelley-side runtime boundary that replaces the disposable helper functions embedded in `server/handlers.go`.

## Likely upstream file

Recommended conceptual target:

- `server/stavrobot.go`

Exact filename can still change later, but this patch should be a focused unit.

## Managed responsibilities

This runtime unit should own:

- installer-managed profile-state loading
- installer-managed profile resolution
- validation of supported schema and bridge contract versions
- bridge argv assembly using literal tokens
- bridge subprocess execution
- bridge JSON output parsing
- S1 text-response adaptation into Shelley assistant messages
- mapping persistence through `UpdateStavrobotMapping()`
- operator-meaningful error classification

## Disposable functions to replace/move

The following disposable functions from `server/handlers.go` should be removed from handlers and replaced here:

- `resolveStavrobotBridgeProfile`
- `runStavrobotTurn`
- `handleStavrobotTurn`

## Recommended internal shapes

Conceptual resolved profile shape:

```go
type ResolvedStavrobotProfile struct {
    Name       string
    BridgePath string
    BaseURL    string
    ConfigPath string
    Args       []string
}
```

Conceptual bridge result shape for S1:

```go
type StavrobotTurnResult struct {
    ResponseText   string
    ConversationID string
    MessageID      string
}
```

Preferred widening direction after S1:

```go
type StavrobotTurnResult struct {
    ResponseText     string
    ConversationID   string
    MessageID        string
    RawBridgePayload *StavrobotBridgePayload
    AssistantContent []llm.Content
    DisplayData      map[string]any
    UnsupportedKinds []string
}
```

Important S2 guardrail:

- the first S1 shape is intentionally minimal
- but patch 0004 should not freeze the runtime boundary into a permanent text-only abstraction
- when the bridge grows stable structured output, this result shape should be allowed to evolve so Shelley can preserve native markdown/media/tool/display semantics rather than flattening everything into `ResponseText`
- `ResponseText` should remain the mandatory fallback even after widening
- the preferred widening guide now lives in `../../../docs/SHELLEY_RUNTIME_ADAPTATION_CONTRACT.md`

## Recommended internal helper boundaries

### `LoadStavrobotBridgeProfiles(...)`

Responsibilities:

- read the installer-managed JSON profile-state file
- parse JSON
- validate root schema/contract versions
- return in-memory profile state

Important:

- target the contract represented today by this repo's prototype loader and sample state file
- do not hardcode `local-default`
- do not hardcode `/tmp/stavrobot/...`
- do not hardcode repo checkout paths

### `ResolveStavrobotBridgeProfile(...)`

Responsibilities:

- take a `bridge_profile` name
- resolve it from loaded state
- verify enabled/profile existence
- verify `bridge_path`, `config_path`, and `base_url`
- return a `ResolvedStavrobotProfile`

### `ExecuteStavrobotTurn(...)`

Responsibilities:

- validate S1-supported user message shape
- resolve profile
- build argv as literal tokens
- execute bridge
- parse bridge JSON output into a `StavrobotTurnResult`
- preserve raw parsed bridge payload when available
- normalize only a narrow supported subset of richer content/display data at first

Near-term widening rule:

- this function should evolve toward returning both normalized fallback fields and richer parsed payload data
- it should not become the place where Shelley UI rendering decisions are made
- the bridge now already emits the first narrow S2-ready fields in practice, so this function should normalize the real canonical `content` / compact `display.tool_summary` / `raw` envelope rather than only carrying hypothetical future placeholders

Expected argv shape for S1:

1. `bridge_path`
2. profile `args`
3. `--config-path <config_path>`
4. `--base-url <base_url>`
5. dynamic turn args such as:
   - `chat`
   - `--message <text>`
   - `--conversation-id <id>` when continuing

### `ProcessStavrobotConversationTurn(...)`

Responsibilities:

- set working state
- record user message in Shelley
- execute Stavrobot turn
- persist remote mapping via `UpdateStavrobotMapping()`
- record assistant message
- notify subscribers
- record operator-visible failure message when needed
- remain the Shelley-side adaptation/recording boundary for richer content/display metadata

Near-term widening rule:

- prefer recording normalized `AssistantContent` when supported
- otherwise fall back to `ResponseText`
- keep compact display metadata separate from the main assistant body when possible

## Error classes this unit should distinguish

At minimum:

- profile state file missing
- invalid JSON
- unsupported schema version
- unsupported bridge contract version
- requested profile missing
- requested profile disabled
- `bridge_path` missing / not executable
- `config_path` missing / unreadable
- invalid `base_url`
- unsupported user-message content shape for S1
- bridge subprocess failure
- bridge output parse failure

## Runtime file-location rule

This runtime unit should not use a source-checkout-relative path in the final cleaned patch.

Preferred final shape:

- Shelley runtime config points to profile-state file

Acceptable S1 fallback:

- a stable installer-managed machine path

Until that is wired in Shelley itself, this repo's prototype loader behavior is the concrete contract target.

## Definition of done for this patch

- handler-local disposable Stavrobot helpers are gone
- focused runtime unit owns all profile loading/resolution logic
- no machine-specific source checkout paths are hardcoded in Shelley source
- no disposable `/tmp/stavrobot/...` mapping assumptions remain in Shelley source
- normal Shelley behavior remains unchanged when Stavrobot mode is off
- Stavrobot mode still satisfies the managed smoke expectations

## Current S1 limitations to keep explicit

The captured prototype runtime patch currently does these S1-specific things:

- requires the incoming user message to start with `llm.ContentTypeText`
- invokes the bridge against the canonical chat envelope, which now already carries:
  - `response`
  - `conversation_id`
  - `message_id`
  - optional `content`
  - optional compact `display.tool_summary`
  - optional `raw`
- currently normalizes `markdown` / `text` bridge content into Shelley text content while preserving `ResponseText` fallback
- currently records compact tool-summary display metadata separately when present
- still classifies `image_ref` and artifact/media shapes as explicit unsupported rich kinds for later S2 follow-up
- keeps room for a richer runtime result shape carrying:
  - raw bridge payload
  - pre-adapted assistant content blocks
  - optional display metadata

These are acceptable S1 constraints, but they should stay documented as current limitations rather than becoming hidden architectural assumptions.

## Runtime adaptation contract pointer

For future implementation sessions, treat this patch note as the patch-local summary and use the repo doc below as the preferred widening contract:

- `../../../docs/SHELLEY_RUNTIME_ADAPTATION_CONTRACT.md`

That doc is the intended reference for:

- raw bridge payload retention
- normalized assistant-content preparation
- compact display metadata handling
- explicit unsupported-kind fallback behavior
- ownership split between `ExecuteStavrobotTurn(...)` and `ProcessStavrobotConversationTurn(...)`

## Future-safe adaptation boundary guidance

Patch 0004 should be treated as the Shelley-side adaptation seam for richer bridge output.

Preferred direction when the bridge evolves:

1. preserve the raw structured bridge payload long enough to adapt it deliberately
2. map richer bridge fields into Shelley-native `llm.Content` / display structures where possible
3. keep markdown-friendly text as markdown-friendly text rather than destructively flattening or escaping it
4. preserve room for tool/display/media references in Shelley message content or associated display metadata
5. preserve Shelley's existing excellent mobile/responsive presentation by adapting into native Shelley content/UI surfaces rather than inventing a parallel Stavrobot-specific presentation layer
6. avoid forcing future S2 work to reverse a `ResponseText`-only abstraction baked too deeply into helper signatures
7. treat the bridge's already-live `content`, compact `display.tool_summary`, and `raw` fields as the concrete first adaptation input, with unsupported media/artifact kinds degrading explicitly until Shelley-native handling is ready

A practical consequence is that `ExecuteStavrobotTurn(...)` and `ProcessStavrobotConversationTurn(...)` should remain easy to widen from:

- `response text only`

toward:

- structured payload in
- Shelley-native content/display mapping out
