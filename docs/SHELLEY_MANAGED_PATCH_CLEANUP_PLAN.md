# Shelley managed patch cleanup plan

## Purpose

Define the concrete cleanup work needed to turn the captured disposable S1 patch artifact into a maintainable managed Shelley patch set.

This is the next step after:

- validating the seam in `/tmp/shelley-official`
- extracting the disposable diff into repo-owned patch assets
- documenting the managed rebuild and cutover recipe

## Current state

The repo now owns a starting patch artifact:

- `patches/shelley/s1-stavrobot-mode-disposable-shape.patch`

That artifact is valuable because it captures a live-validated upstream diff.

But it still contains disposable validation scaffolding and should not be treated as the final managed patch.

## Cleanup goal

Produce a maintained Shelley patch set that preserves the validated seam while removing disposable local assumptions.

## The three biggest cleanup targets

## 1. Replace hardcoded bridge/profile resolution

### Disposable shape

The disposable spike resolved bridge/profile information with hardcoded assumptions inside Shelley source, including:

- fixed bridge script path in this repo checkout
- fixed `local-default` special case
- fixed Stavrobot config path under `/tmp/stavrobot/...`
- fixed local base URL

### Managed target

Shelley should resolve:

- canonical bridge path
- named bridge profile
- local profile config

from installer-managed state.

### Why this matters

Without this cleanup, the patch remains tied to a disposable test-bed layout instead of the actual installer-managed deployment model.

## 2. Separate runtime integration concerns from route handlers

### Disposable shape

The spike put bridge invocation, profile resolution, output parsing, and message recording logic mostly into `server/handlers.go`.

### Managed target

Keep only the routing branch and mode dispatch decision in the handler layer.

Move Stavrobot-specific integration behavior into a focused unit/service/module.

### Why this matters

- easier maintenance against upstream changes
- lower handler complexity
- clearer testing surface
- cleaner later S2 evolution for structured output fidelity

## 3. Preserve S1 simplicity without freezing the wrong abstractions

### Disposable shape

The spike is text-first and plain-text-only.

### Managed target

S1 can remain text-first, but the cleaned patch should make it obvious that:

- unsupported richer content is an S1 limitation
- not an architectural claim that Shelley/Stavrobot must stay plain-text forever

### Why this matters

Shelley has richer native capabilities that S2 should preserve or exploit later.

## Recommended cleaned patch structure

A maintainable managed patch set should likely be organized around these concerns.

## A. Metadata and schema support

Owns:

- `ConversationOptions` extension
- `StavrobotOptions`
- `IsStavrobot()` helper
- SQL query addition for `UpdateConversationOptions`
- regenerated sqlc output
- UI type extension for `conversation_options`

Primary upstream files:

- `db/db.go`
- `db/query/conversations.sql`
- `db/generated/conversations.sql.go`
- `ui/src/types.ts`

## B. Conversation manager support

Owns:

- mode detection on conversation manager
- accessors for Stavrobot options
- mapping persistence helper

Primary upstream file:

- `server/convo.go`

## C. Conversation route branching

Owns:

- new conversation route choosing normal vs Stavrobot path
- chat route choosing normal vs Stavrobot path
- Stavrobot-mode request validation
- queue-mode limitations for S1 if still needed

Primary upstream file:

- handler/runtime route surface

## D. Focused Stavrobot runtime integration unit

Owns:

- installer-managed bridge/profile resolution
- bridge invocation
- structured JSON output parsing
- S1 assistant message adaptation
- error recording behavior
- persistence hook invocation

Primary upstream file(s):

- likely a new focused server/runtime file in Shelley
- or another minimal isolated integration unit

## Recommended installer-managed state dependency for cleaned patch

The cleaned patch should assume a small installer-managed resolution surface exists, conceptually something like:

- canonical bridge path
- available bridge profile names
- mapping from profile name to local config facts

The cleaned Shelley patch should not need to know how the installer created that state. It only needs a stable local read/resolve contract.

## Practical cleanup sequence

### Step 1

Keep metadata/schema pieces largely as validated.

These appear close to the right final shape already.

### Step 2

Extract bridge/profile/runtime logic from the disposable handler-heavy shape into a focused integration unit.

### Step 3

Replace disposable local profile resolution with installer-managed resolution hooks.

### Step 4

Update the smoke driver assumptions if needed to match the cleaned managed runtime shape.

### Step 5

Treat the cleaned patch set as the new managed source of truth, not the disposable-shape patch.

## What should probably remain unchanged from the validated shape

These parts already look like real design signal:

- per-conversation mode in `conversation_options`
- branch above provider/model layer
- reuse existing Shelley message persistence
- reuse existing working-state UX
- persist remote `conversation_id` and `last_message_id`
- keep bridge-facing Shelley contract narrow

## Definition of success for cleanup

The cleanup should be considered successful when:

- the patch no longer hardcodes repo-local bridge paths
- the patch no longer hardcodes `/tmp/stavrobot/...` config assumptions
- the patch no longer hardcodes one disposable `local-default` profile mapping in Shelley source
- the patch still passes the owned managed S1 smoke driver
- the patch remains refreshable against upstream Shelley with reasonable maintenance cost

## Immediate next practical artifact after this plan

The next useful artifact would be one of:

1. a cleaned patch series under `patches/shelley/`
2. a scripted patch applier owned by this repo
3. a small prototype of installer-managed bridge profile state that the cleaned Shelley patch would resolve

Of those, the highest-value next step is probably:

- define the smallest concrete installer-managed bridge profile resolution contract that the cleaned Shelley patch can depend on

That would let the patch cleanup remove the biggest disposable assumption first.
