# Shelley cleaned patch series shape

## Purpose

Define the concrete managed patch-series shape that should replace the captured disposable S1 diff.

This document is the first step from:

- a validated but disposable upstream patch artifact

to:

- a maintainable cleaned patch set this repo can own and refresh

## Guiding rule

Keep the validated seam.

Change the disposable implementation shape.

That means:

- keep per-conversation mode in `conversation_options`
- keep branching above the provider/model layer
- keep existing Shelley message persistence and working-state reuse
- keep the canonical bridge contract

But:

- remove hardcoded profile/path assumptions
- reduce handler bulk
- isolate Stavrobot-specific runtime logic behind a narrower Shelley-side boundary

## Recommended patch-series split

The cleaned patch should likely be owned as a small series rather than one large mixed diff.

## Patch 1: metadata, SQL, and UI type support

### Responsibility

Add the minimum structural support for Stavrobot mode metadata.

### Upstream files

- `db/db.go`
- `db/query/conversations.sql`
- `db/generated/conversations.sql.go`
- `ui/src/types.ts`

### What stays close to the disposable shape

These parts already looked close to the right managed shape:

- `ConversationOptions` gains Stavrobot metadata
- `StavrobotOptions` struct exists
- `IsStavrobot()` helper exists
- `UpdateConversationOptions` query exists
- frontend API type understands Stavrobot-capable `conversation_options`

### Expected managed changes

Minimal.

This patch should remain very close to the validated spike.

## Patch 2: conversation manager support

### Responsibility

Add conversation-manager helpers for mode detection and remote mapping persistence.

### Upstream file

- `server/convo.go`

### What stays close to the disposable shape

- `IsStavrobotMode()`
- `StavrobotOptions()` accessor
- `UpdateStavrobotMapping()` helper

### Expected managed changes

Minimal.

This also looked close to the right managed shape already.

## Patch 3: route branching only

### Responsibility

Keep route-level mode branching, but remove bulky runtime details from handlers.

### Upstream file

- `server/handlers.go`

### Managed target behavior

`handleNewConversation` and `handleChatConversation` should still:

- detect whether the conversation is in Stavrobot mode
- branch above the normal LLM/provider path
- preserve ordinary Shelley behavior when mode is off

But they should no longer directly own:

- hardcoded profile resolution
- bridge argv construction rules
- bridge invocation internals
- bridge JSON parsing details
- most of the Stavrobot runtime execution flow

### Practical result

Handler changes become thinner and easier to maintain.

## Patch 4: focused Stavrobot runtime integration unit

### Responsibility

Move disposable runtime integration logic into a focused Shelley-side unit.

### Likely new upstream file

Recommended conceptual target:

- `server/stavrobot.go`

Exact filename can change later, but a focused dedicated file is the right shape.

### Responsibilities of this unit

- load and resolve installer-managed bridge profile state
- validate supported schema and bridge contract versions
- resolve `bridge_profile` name into:
  - `bridge_path`
  - `base_url`
  - `config_path`
  - installer-managed default args
- invoke the canonical bridge with literal argv tokens
- parse bridge JSON output
- map S1 text response into Shelley assistant message
- record operator-meaningful errors
- call `UpdateStavrobotMapping()` after successful turn

## Exact disposable functions that should be replaced or moved

From the captured disposable patch shape in `server/handlers.go`, these are the main functions to replace/move:

### Disposable function: `resolveStavrobotBridgeProfile`

Current problem:

- hardcodes bridge script path
- hardcodes `local-default`
- hardcodes `/tmp/stavrobot/...`
- hardcodes `http://localhost:8000`

Managed replacement target:

- `LoadStavrobotBridgeProfiles(...)`
- `ResolveStavrobotBridgeProfile(...)`

These should read installer-managed profile state using the bridge-resolution contract from:

- `docs/SHELLEY_BRIDGE_PROFILE_RESOLUTION_CONTRACT.md`

### Disposable function: `runStavrobotTurn`

Current problem:

- too much bridge execution logic sits in handler file
- directly tied to disposable profile resolver

Managed replacement target:

A focused runtime function such as conceptually:

- `ExecuteStavrobotTurn(...)`

Responsibilities:

- validate S1-supported message shape
- resolve profile
- assemble argv
- invoke bridge
- parse bridge JSON result

### Disposable function: `handleStavrobotTurn`

Current problem:

- reasonable high-level behavior, but currently lives in the wrong place and depends on disposable runtime pieces

Managed replacement target:

A focused runtime entry such as conceptually:

- `ProcessStavrobotConversationTurn(...)`

Responsibilities:

- set working state
- record user message
- execute Stavrobot turn
- persist returned mapping
- record assistant message
- notify subscribers

The route handlers can then call this runtime entry cleanly.

## Recommended cleaned internal data shapes

The cleaned runtime unit likely needs one resolved internal type conceptually like:

```go
type ResolvedStavrobotProfile struct {
    Name       string
    BridgePath string
    BaseURL    string
    ConfigPath string
    Args       []string
}
```

And one bridge-output type conceptually like:

```go
type StavrobotTurnResult struct {
    ResponseText   string
    ConversationID string
    MessageID      string
}
```

These are enough for S1.

## Recommended file-read boundary

The cleaned runtime unit should own all installer-managed profile-file reading/validation.

That means route handlers should not know about:

- JSON file paths
- schema version checks
- bridge contract version checks
- profile file parsing details

They should only know whether a Stavrobot turn succeeded or failed.

## Recommended cleaned error taxonomy

The cleaned runtime unit should distinguish errors like:

- missing/invalid profile state file
- unsupported schema version
- unsupported bridge contract version
- missing/disabled profile
- missing/non-executable bridge path
- missing/unreadable config path
- unsupported S1 message content shape
- bridge execution failure
- bridge JSON parse failure
- mapping persistence failure
- assistant message persistence failure

This is much better than leaving all failure modes as generic handler-local errors.

## Recommended route-handler end state

After cleanup, route handlers should conceptually read more like:

1. determine conversation mode
2. if normal mode:
   - proceed as upstream Shelley already does
3. if Stavrobot mode:
   - call focused runtime entry
   - translate success/failure into HTTP response

That is the clean target shape.

## Recommended smoke-test implications

The owned smoke driver does not need major conceptual change.

But once the cleaned patch exists, the smoke path should implicitly validate that:

- no hardcoded disposable `local-default` mapping remains in Shelley source
- profile resolution comes from installer-managed state
- ordinary Shelley behavior still passes side by side with Stavrobot mode

## Recommended next repo asset after this document

The next useful repo-owned artifact should be one of:

1. a cleaned patch-series skeleton under `patches/shelley/`
2. a scripted patch-applier that introduces the new `server/stavrobot.go`-style runtime unit
3. a prototype installer-managed `state/shelley-bridge-profiles.json` file plus loader assumptions

Of those, the highest-value next artifact was:

- a prototype installer-managed `state/shelley-bridge-profiles.json` sample plus loader/read-path assumptions

That prototype now exists in this repo as:

- `state/shelley-bridge-profiles.json`
- `py/shelley_bridge_profiles.py`
- `manage-shelley-bridge-profiles.sh`

So the next practical engineering step is no longer contract definition.

It is to start the cleaned Shelley-side runtime implementation around the focused boundary described above, using the prototype profile-state loader behavior as the runtime target for:

- `LoadStavrobotBridgeProfiles(...)`
- `ResolveStavrobotBridgeProfile(...)`
- `ExecuteStavrobotTurn(...)`
- `ProcessStavrobotConversationTurn(...)`

## Repo-owned series skeleton status

This repo now also includes a first patch-series skeleton under:

- `patches/shelley/series/`

Current purpose of that skeleton:

- turn the cleaned patch split from prose into owned patch-by-patch implementation targets
- make the next engineering session work against a maintained split instead of against the whole disposable diff
- keep patch 3 thin and push real runtime ownership into patch 4

Current limitation:

- these are design/implementation skeleton files, not apply-ready patch hunks yet
- the next step after the skeleton is to convert at least patch 4 into concrete maintained patch material or a scripted patch applier

## Repo-owned patch-4 apply scaffold status

The repo now also includes a function-by-function apply scaffold for the focused runtime unit at:

- `patches/shelley/series/0004-stavrobot-runtime-unit.patch-plan.md`

That scaffold is the first concrete bridge from:

- disposable helper functions in `server/handlers.go`

to:

- a maintained `server/stavrobot.go`-style runtime unit

It is still not an apply-ready patch hunk file yet, but it should now be possible to write the first real maintained patch for patch 4 without re-deriving the function split or helper responsibilities from scratch.

## First managed upstream runtime prototype status

The repo now also contains a first real cleaned-runtime prototype diff captured from a managed `/opt/shelley` checkout:

- `patches/shelley/s1-stavrobot-mode-cleaned-runtime-prototype.patch`

What this prototype now proves:

- a focused `server/stavrobot.go` runtime unit can replace the disposable handler-local helper functions
- `server/handlers.go` can stay at the route-branching layer
- the runtime unit can target installer-managed profile-state loading/resolution instead of hardcoded disposable `local-default` mapping logic

Current limitation:

- this is still a prototype diff, not yet the final patch-series split into apply-ready hunks
- the runtime path currently uses a stable fallback path plus env override for the profile-state file until a fuller Shelley runtime config hook is chosen
