# Patch 0004 apply plan: focused Stavrobot runtime integration unit

## Purpose

Turn patch 0004 from a conceptual target into a function-by-function implementation scaffold.

This file is the bridge between:

- the disposable runtime helpers captured in `../s1-stavrobot-mode-disposable-shape.patch`
- the cleaned runtime-unit target in `0004-stavrobot-runtime-unit.md`
- the eventual apply-ready maintained Shelley patch against upstream

## Scope

This plan only covers the focused runtime-unit work.

It does **not** redefine:

- metadata / SQL / UI changes
- conversation-manager helper changes
- handler branch points beyond the minimal call-site shape needed for this unit

## Proposed upstream file shape

Primary target:

- `server/stavrobot.go`

Secondary touch point:

- `server/handlers.go`

Goal:

- move Stavrobot runtime mechanics into `server/stavrobot.go`
- leave handlers with only mode validation + dispatch

## Disposable-to-clean mapping

### 1. Disposable `resolveStavrobotBridgeProfile`

Current disposable behavior:

- returns bridge path and argv prefix
- hardcodes repo checkout bridge path
- hardcodes `local-default`
- hardcodes `/tmp/stavrobot/data/main/config.toml`
- hardcodes `http://localhost:8000`

Clean target split:

- `LoadStavrobotBridgeProfiles(...)`
- `ResolveStavrobotBridgeProfile(...)`

### 2. Disposable `runStavrobotTurn`

Current disposable behavior:

- validates plain-text user message assumption
- resolves disposable profile
- builds argv
- invokes bridge
- parses response JSON

Clean target replacement:

- `ExecuteStavrobotTurn(...)`

### 3. Disposable `handleStavrobotTurn`

Current disposable behavior:

- sets working state
- records user message
- executes Stavrobot turn
- persists mapping
- records assistant/error message
- notifies subscribers

Clean target replacement:

- `ProcessStavrobotConversationTurn(...)`

## Proposed internal types

```go
type StavrobotBridgeProfiles struct {
    SchemaVersion         int                               `json:"schema_version"`
    BridgeContractVersion int                               `json:"bridge_contract_version"`
    DefaultProfile        string                            `json:"default_profile"`
    Profiles              map[string]StavrobotBridgeProfile `json:"profiles"`
}

type StavrobotBridgeProfile struct {
    Enabled    bool     `json:"enabled"`
    BridgePath string   `json:"bridge_path"`
    BaseURL    string   `json:"base_url"`
    ConfigPath string   `json:"config_path"`
    Args       []string `json:"args"`
    Notes      string   `json:"notes,omitempty"`
}

type ResolvedStavrobotProfile struct {
    Name       string
    BridgePath string
    BaseURL    string
    ConfigPath string
    Args       []string
}

type StavrobotTurnResult struct {
    ResponseText   string
    ConversationID string
    MessageID      string
}
```

Notes:

- naming can still change slightly to match Shelley conventions
- the important point is separating raw loaded profile state from validated resolved runtime state

## Proposed helper set in `server/stavrobot.go`

### `func (s *Server) stavrobotProfileStatePath() string`

Responsibility:

- return the configured profile-state file path Shelley should read

Preferred eventual source:

- explicit Shelley runtime config

Acceptable S1 fallback:

- stable installer-managed machine path

Temporary implementation note:

- if an upstream Shelley runtime config hook does not exist yet, this function becomes the single temporary place where the S1 fallback path is chosen
- this avoids scattering file-path assumptions across the code

### `func LoadStavrobotBridgeProfiles(path string) (*StavrobotBridgeProfiles, error)`

Responsibilities:

- read JSON file
- unmarshal into Go struct
- validate root object and supported versions
- return parsed state

Suggested validation:

- file exists/readable
- valid JSON
- `schema_version == 1`
- `bridge_contract_version == 1`
- `profiles` is non-nil
- `default_profile` non-empty

Suggested error wrapping examples:

- `stavrobot profile state file missing`
- `stavrobot profile state invalid JSON`
- `unsupported stavrobot profile schema version`
- `unsupported stavrobot bridge contract version`

### `func ResolveStavrobotBridgeProfile(state *StavrobotBridgeProfiles, name string) (*ResolvedStavrobotProfile, error)`

Responsibilities:

- validate requested profile name
- look up named profile
- validate enabled/profile fields
- validate bridge path/config path/base URL
- return resolved profile

Suggested validation:

- requested name non-empty
- profile exists
- profile enabled
- `bridge_path` absolute and executable
- `config_path` absolute and readable
- `base_url` parseable with `http` or `https` scheme
- `args` all strings (in Go struct this mostly becomes normalization)

Suggested error wrapping examples:

- `stavrobot bridge profile missing`
- `stavrobot bridge profile disabled`
- `stavrobot bridge path not executable`
- `stavrobot config path not readable`
- `stavrobot base URL invalid`

### `func ExecuteStavrobotTurn(ctx context.Context, profile *ResolvedStavrobotProfile, opts *db.StavrobotOptions, userMessage llm.Message) (*StavrobotTurnResult, error)`

Responsibilities:

- enforce S1 text-only input expectation
- build argv literally
- execute bridge subprocess
- parse returned JSON
- return structured result

Suggested argv assembly:

```go
args := append([]string{}, profile.Args...)
args = append(args,
    "--config-path", profile.ConfigPath,
    "--base-url", profile.BaseURL,
    "chat",
    "--message", text,
)
if opts.ConversationID != "" {
    args = append(args, "--conversation-id", opts.ConversationID)
}
```

Suggested bridge payload parse shape:

```go
var payload struct {
    Response       string `json:"response"`
    ConversationID string `json:"conversation_id"`
    MessageID      string `json:"message_id"`
}
```

Suggested validation:

- user message has at least one content item
- first content item is text
- response JSON parses cleanly
- empty `response` may be allowed for now if bridge contract allows it, but should be reviewed explicitly

Suggested error wrapping examples:

- `stavrobot mode currently requires plain text user messages`
- `stavrobot bridge execution failed`
- `failed to parse stavrobot bridge output`

### `func (s *Server) ProcessStavrobotConversationTurn(ctx context.Context, manager *ConversationManager, userMessage llm.Message) error`

Responsibilities:

- get conversation Stavrobot options
- load + resolve profile state
- set agent working state
- record user message
- execute bridge turn
- persist updated mapping
- record assistant or error message
- notify subscribers

Suggested flow:

1. validate manager not nil
2. fetch `opts := manager.StavrobotOptions()`
3. load profile state from `s.stavrobotProfileStatePath()`
4. resolve `opts.BridgeProfile`
5. `manager.SetAgentWorking(true)` with defer false
6. record user message
7. execute turn
8. if execution fails:
   - record assistant-visible `[Stavrobot error] ...` message
   - return error
9. if remote IDs present:
   - call `manager.UpdateStavrobotMapping(...)`
10. record assistant message with Stavrobot metadata in `userData`
11. notify subscribers
12. return nil

## Minimal handler change target after runtime extraction

After `server/stavrobot.go` exists, handlers should conceptually look like:

```go
if manager.IsStavrobotMode() {
    if err := s.ProcessStavrobotConversationTurn(ctx, manager, userMessage); err != nil {
        // log + HTTP error
    }
    // accepted response
    return
}
```

No handler-local profile resolution or bridge invocation logic should remain.

## Recommended implementation sequence

### Step 1

Add `server/stavrobot.go` with types + profile loading/resolution helpers.

### Step 2

Move bridge execution logic into `ExecuteStavrobotTurn(...)`.

### Step 3

Move conversation-turn orchestration into `ProcessStavrobotConversationTurn(...)`.

### Step 4

Reduce handler changes to pure branching + error translation.

### Step 5

Delete disposable helper implementations from `server/handlers.go`.

## Suggested first apply-ready patch boundaries

If this is converted into real maintained patch hunks, the likely order should be:

1. add `server/stavrobot.go`
2. update handler call sites to use the new runtime entrypoint
3. remove old disposable helper functions from `server/handlers.go`

This order keeps the diff reviewable and avoids a giant mixed rewrite.

## Open implementation choices still intentionally left open

These should be decided when writing the actual upstream patch:

- exact config source for the profile-state file path
- whether profile state should be cached or loaded per turn in S1
- exact error type mapping into Shelley runtime/UI semantics
- whether empty bridge responses are allowed or normalized in S1

## Definition of done for this apply plan

This plan is successful when a future implementation session can take it and write the first concrete maintained `server/stavrobot.go` patch without needing to rediscover how the disposable helper functions should be split or what each new function should own.

## S2 widening note for helper signatures

When refining the prototype runtime patch, prefer helper boundaries that can widen without a major rewrite.

For example:

- `ExecuteStavrobotTurn(...)` should ideally evolve from returning only parsed S1 text fields toward returning either:
  - a richer structured result type
  - or a raw bridge payload plus normalized fields
- `ProcessStavrobotConversationTurn(...)` should remain the place that maps bridge output into Shelley-native recorded message content and display metadata

Why this matters:

Shelley already has native notions of content blocks, tool output, and display metadata. Even though the current `llm.Content` model is still limited, patch 0004 should avoid making `ResponseText` the only permanent conceptual output of the runtime layer.

That keeps the path open for later support of:

- markdown-preserving responses
- richer display metadata
- tool/event summaries or references
- media/screenshot/HTML-oriented adaptation work when Shelley and the bridge are ready

## Mobile / responsive presentation guardrail

Any future widening of patch 0004 should preserve upstream Shelley's existing mobile/responsive presentation quality.

Practical implication:

- prefer mapping richer Stavrobot output into existing Shelley-native message/content/display affordances
- avoid introducing a parallel Stavrobot-only rendering surface that would need separate mobile/responsive behavior
- keep the runtime patch focused on producing data that upstream Shelley UI can already present well, or can extend naturally without regressing small-screen behavior

## Prototype-hardening note captured after split review

The current managed `/opt/shelley` prototype has now been lightly refined so `StavrobotTurnResult` is less text-locked even while preserving S1 behavior.

Current improved shape includes room for:

- raw bridge payload retention
- assistant-content blocks prepared for Shelley recording
- optional display metadata

This is still S1 behaviorally text-first, but it is a better S2 starting point because the runtime result no longer implies that plain response text is the only meaningful output of the bridge/runtime boundary.

See also:

- `docs/SHELLEY_RUNTIME_ADAPTATION_CONTRACT.md`

That contract is the preferred widening guide for patch `0004` when future sessions refine `ExecuteStavrobotTurn(...)` and `ProcessStavrobotConversationTurn(...)` toward structured bridge content/display/artifact adaptation.
