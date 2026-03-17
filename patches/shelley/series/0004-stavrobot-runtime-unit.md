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

Important S2 guardrail:

- this S1 shape is intentionally minimal
- but patch 0004 should not freeze the runtime boundary into a permanent text-only abstraction
- when the bridge grows stable structured output, this result shape should be allowed to evolve so Shelley can preserve native markdown/media/tool/display semantics rather than flattening everything into `ResponseText`

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
- invokes the bridge expecting a minimal JSON shape with:
  - `response`
  - `conversation_id`
  - `message_id`
- records the returned assistant content as a single Shelley text content block

These are acceptable S1 constraints, but they should stay documented as current limitations rather than becoming hidden architectural assumptions.

## Future-safe adaptation boundary guidance

Patch 0004 should be treated as the Shelley-side adaptation seam for richer bridge output.

Preferred direction when the bridge evolves:

1. preserve the raw structured bridge payload long enough to adapt it deliberately
2. map richer bridge fields into Shelley-native `llm.Content` / display structures where possible
3. keep markdown-friendly text as markdown-friendly text rather than destructively flattening or escaping it
4. preserve room for tool/display/media references in Shelley message content or associated display metadata
5. avoid forcing future S2 work to reverse a `ResponseText`-only abstraction baked too deeply into helper signatures

A practical consequence is that `ExecuteStavrobotTurn(...)` and `ProcessStavrobotConversationTurn(...)` should remain easy to widen from:

- `response text only`

toward:

- structured payload in
- Shelley-native content/display mapping out
