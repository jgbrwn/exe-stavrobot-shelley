# Shelley S1 disposable spike extraction

## Purpose

Capture the validated design signal from the disposable `/tmp/shelley-official` S1 spike without treating that checkout or patch as production-ready code.

This document is the bridge between:

- **validated seam proof** from the disposable official Shelley spike
- **future managed rebuild/integration work** that this repo should eventually automate

## Bottom line

The disposable S1 spike proved that optional per-conversation Stavrobot mode can work in official Shelley by branching in the **server conversation handlers**, not by pretending Stavrobot is a normal model/provider.

That is the real signal to carry forward.

The disposable hardcoded bridge path, local config path, and test profile mapping were only validation scaffolding.

## Exact minimal patch shape observed in `/tmp/shelley-official`

Files touched in the disposable spike:

1. `db/db.go`
   - extended `ConversationOptions`
   - added `StavrobotOptions`
   - added `IsStavrobot()` helper

2. `ui/src/types.ts`
   - extended frontend API typing for `conversation_options`
   - added Stavrobot-capable shape with:
     - `type`
     - `stavrobot.enabled`
     - `stavrobot.conversation_id`
     - `stavrobot.last_message_id`
     - `stavrobot.bridge_profile`

3. `server/handlers.go`
   - branched in `handleNewConversation`
   - branched in `handleChatConversation`
   - added disposable bridge-profile resolution
   - added bridge invocation and JSON parsing
   - recorded assistant reply back through normal Shelley message flow
   - reused Shelley working-state handling

4. `server/convo.go`
   - added accessors for Stavrobot mode/options on `ConversationManager`
   - added metadata persistence helper for remote mapping updates

5. `db/query/conversations.sql`
   - added `UpdateConversationOptions`

6. generated sqlc output
   - regenerated to expose `UpdateConversationOptions`

## Responsibilities that appear to be real design signal

These look like durable architectural conclusions, not temporary hacks:

### 1. Branch above the provider layer

The validated branch point was in conversation route handling.

Why this matters:

- Stavrobot is a higher-level agent service, not just another raw model endpoint
- Shelley already has its own conversation/message/working-state machinery
- the mode can preserve default Shelley behavior when off

### 2. Keep Stavrobot state in `conversation_options`

Validated minimal per-conversation data:

```json
{
  "type": "stavrobot",
  "stavrobot": {
    "enabled": true,
    "conversation_id": "conv_1",
    "last_message_id": "msg_110",
    "bridge_profile": "local-default"
  }
}
```

Why this matters:

- state is conversation-scoped
- metadata is small
- metadata stays secret-free
- normal conversations remain unaffected

### 3. Reuse Shelley message persistence and working-state UX

The disposable spike reused existing Shelley behavior for:

- user message recording
- assistant message recording
- `Agent Working...` / in-flight state
- subscriber notification / normal conversation updates

Why this matters:

- minimizes blast radius
- keeps Stavrobot mode looking like a first-class Shelley conversation
- reduces the amount of custom UI/runtime logic needed for S1

### 4. Treat the canonical contract as the bridge script

Validated Shelley-facing contract:

- Shelley should call `shelley-stavrobot-bridge.sh`
- Shelley should not embed lower-level client/session logic directly
- lower-level wrappers remain implementation details and operator tools

### 5. Persist remote mapping after each successful turn

The key mutable state was:

- remote `conversation_id`
- remote `last_message_id`

Why this matters:

- proves active-thread continuation
- avoids replaying full local transcript through a fake provider path
- supports long-lived Shelley conversations backed by Stavrobot-owned thread state

## Disposable spike details that should **not** be carried forward as-is

These were useful for proving the seam, but should be replaced in a managed implementation:

### Hardcoded machine-local bridge path

Disposable spike used a fixed path similar to:

- `/home/exedev/exe-stavrobot-shelley/shelley-stavrobot-bridge.sh`

Managed implementation should instead resolve bridge location from installer-managed local state.

### Hardcoded local profile mapping

Disposable spike special-cased:

- `bridge_profile = "local-default"`
- fixed config path under `/tmp/stavrobot/...`
- fixed base URL `http://localhost:8000`

Managed implementation should instead load installer-managed profile definitions.

### Inline bridge JSON parsing inside route handlers

The disposable spike was acceptable for validation, but a cleaner real patch should isolate:

- bridge profile resolution
- bridge invocation
- output parsing
- error classification

into a small Shelley-side Stavrobot integration module/service.

### Plain-text-only assumptions

Disposable spike only handled plain text user input and plain text assistant output.

That is acceptable for S1 validation, but must not become the long-term ceiling because Shelley has richer native capabilities.

## Recommended managed rebuild target for S1

The future managed Shelley rebuild should preserve the validated seam while cleaning up implementation shape.

### Keep

- per-conversation optional mode
- branch in conversation/server flow
- `conversation_options` metadata shape
- reuse existing Shelley message + working-state plumbing
- canonical bridge contract
- persistence of remote mapping after each turn

### Change

- replace hardcoded bridge/profile resolution with installer-managed state lookup
- move Stavrobot-specific runtime code out of bulky route handlers into a focused integration unit
- define a small stable bridge-output contract for S1
- explicitly classify unsupported content for S1 instead of silently flattening everything

## Recommended code responsibilities for a real Shelley patch

A cleaner managed Shelley patch likely needs these responsibilities:

### A. Conversation option model

Owns:

- Stavrobot-capable `conversation_options` schema
- mode detection helpers
- validation rules for required fields

### B. Conversation runtime branch

Owns:

- deciding normal vs Stavrobot path for new-turn handling
- preserving default Shelley flow when mode is off

### C. Stavrobot bridge runner

Owns:

- resolving `bridge_profile`
- invoking `shelley-stavrobot-bridge.sh`
- parsing structured output
- converting failures into Shelley-visible error behavior

### D. Mapping persistence helper

Owns:

- updating `conversation_options.stavrobot.conversation_id`
- updating `conversation_options.stavrobot.last_message_id`
- keeping metadata write path isolated and testable

### E. Message adaptation layer

Owns:

- S1: text-only mapping into Shelley messages
- later S2+: richer markdown/media/tool/display adaptation

## Stable S1 bridge expectations

The managed S1 implementation should assume a narrow bridge contract.

Minimum useful output fields:

- `response`
- `conversation_id`
- `message_id`

Likely S1 requirements:

- deterministic JSON output
- non-zero exit on transport/runtime failures
- secret-free metadata in Shelley conversation state
- profile-based local resolution outside conversation metadata

## Suggested installer-managed rebuild implications

This repo should eventually automate a repeatable Shelley rebuild flow that reproduces the validated S1 shape.

That flow should manage at least:

- Shelley upstream checkout location
- Shelley upstream commit/hash used for the rebuild
- local patch/rebuild version for Stavrobot mode
- local bridge path
- available bridge profiles and their machine-local config
- staleness detection for when Shelley rebuild or profile refresh is needed

## Immediate next implementation work implied by the spike

1. define the managed patch shape from the validated seam
2. define installer-owned bridge profile state and resolution rules
3. define the smallest repeatable rebuild/update flow for an upstream Shelley checkout
4. keep S2 separate so richer markdown/media/tool/HTML fidelity work does not blur S1 cleanup

## S2 note

S2 should be driven by preserving Shelley-native capabilities, not by replacing them with a plain text tunnel.

Important Shelley-native areas to preserve or explicitly account for later:

- markdown rendering
- images/media
- tool output and display metadata
- HTML rendering/presentation
- any other existing structured content/display affordances discovered during implementation

So S1 should stay intentionally small, while S2 should evolve the bridge and adaptation layer toward richer Shelley-native output fidelity.
