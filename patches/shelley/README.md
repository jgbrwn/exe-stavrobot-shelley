# Shelley managed patch assets

## Purpose

This directory holds repo-owned assets for the future managed Shelley Stavrobot-mode rebuild path.

It is the handoff point between:

- the validated disposable S1 spike diff
- the managed rebuild recipe
- the eventual cleaned/maintained patch set this repo should own

## Current contents

### `s1-stavrobot-mode-disposable-shape.patch`

This file captures the validated disposable upstream diff shape extracted from `/tmp/shelley-official`.

It is useful because it proves:

- the patch seam works
- the touched upstream files are known
- the minimum behavior is already validated live

But it is **not** yet the final managed patch set.

### `series/`

This directory now holds a repo-owned cleaned managed patch series.

It now includes first replay/test-validated prototype patch artifacts, though it should still not be treated as the final smoke-validated maintained patch set.

It exists to split the future maintained patch into the concrete owned concerns already identified in the docs:

1. metadata / SQL / UI
2. conversation manager support
3. route branching only
4. focused Stavrobot runtime integration unit

## What still has to be cleaned before this becomes the real managed patch

The disposable patch contains validation scaffolding that should not remain in the maintained patch set.

### 1. Remove hardcoded bridge path assumptions

Disposable spike behavior included a fixed path like:

- `/home/exedev/exe-stavrobot-shelley/shelley-stavrobot-bridge.sh`

Managed patch target:

- Shelley should resolve the canonical bridge path from installer-managed local state
- no machine-specific source checkout path should be embedded in Shelley source

### 2. Remove hardcoded profile mapping assumptions

Disposable spike behavior special-cased:

- `bridge_profile = "local-default"`
- fixed Stavrobot config path under `/tmp/stavrobot/...`
- fixed base URL `http://localhost:8000`

Managed patch target:

- `bridge_profile` remains a conversation-scoped name only
- local profile resolution comes from installer-managed state
- profile definitions remain outside Shelley conversation metadata

### 3. Move runtime integration logic out of bulky route handlers where practical

Disposable spike concentrated bridge/profile/runtime logic inside `server/handlers.go`.

Managed patch target:

- keep route branching in handlers/runtime layer
- move Stavrobot-specific runtime work into a focused integration unit where practical

A likely eventual shape could be something conceptually like:

- `server/stavrobot.go`
- or another small focused runtime module

Even if filenames change later, the design goal is the same: reduce handler bulk and isolate Stavrobot-specific behavior.

### 4. Preserve only the real upstream file ownership

The long-term managed patch should still conceptually own the same functional surfaces:

- `db/db.go`
- `db/query/conversations.sql`
- `db/generated/conversations.sql.go`
- `ui/src/types.ts`
- `server/convo.go`
- handler/runtime integration surface

But it should own them with cleaned implementation shape, not with disposable local assumptions.

### 5. Keep S1 intentionally text-first

The managed S1 patch should not overfit around rich output yet.

But it should also avoid baking in long-term plain-text-only assumptions where they are not necessary.

Managed patch target:

- text-first S1 adaptation path
- explicit unsupported-content behavior where needed
- room for S2 structured markdown/media/tool/HTML fidelity later

## Recommended next patch asset to add here

After the disposable-shape patch, the next useful asset in this directory should be one of:

1. a cleaned managed patch file
2. a patch series split by concern
3. scripted patch application helpers that reproduce the cleaned shape deterministically

## Recommended cleaned patch split

A maintainable managed patch could eventually be split conceptually into pieces like:

### Patch A: metadata + SQL support

Owns:

- `ConversationOptions` extension
- `StavrobotOptions`
- `UpdateConversationOptions`
- regenerated sqlc output
- UI type support

### Patch B: conversation runtime branching

Owns:

- new-conversation branch
- chat-conversation branch
- validation of Stavrobot conversation options
- preservation of normal Shelley behavior when off

### Patch C: Stavrobot runtime integration unit

Owns:

- bridge profile resolution from installer-managed state
- bridge invocation
- bridge output parsing
- assistant/user message adaptation for S1
- error classification
- mapping persistence hook calls

This split is not mandatory, but it is likely cleaner than a single giant mixed patch.

## Definition of done for the cleaned managed patch

The disposable shape should be considered successfully converted into a real managed patch set when:

- no machine-specific source checkout paths are hardcoded in Shelley source
- no disposable `/tmp/stavrobot/...` assumptions remain in Shelley source
- `bridge_profile` is resolved through installer-managed state
- normal Shelley behavior still works unchanged when Stavrobot mode is off
- Stavrobot mode still passes the owned smoke driver
- the patch is maintainable enough to refresh against upstream without relying on the disposable checkout


## Cleaned managed patch-series shape

The concrete target shape for converting the disposable patch artifact into a maintainable managed patch series now lives in:

- `docs/SHELLEY_CLEANED_PATCH_SERIES_SHAPE.md`

That document identifies:

- which parts of the disposable patch can stay close to final shape
- which handler-local functions must be moved/replaced
- the likely new focused Shelley runtime unit boundary for Stavrobot integration

## Current concrete next-step asset

The repo now also includes a focused apply scaffold for the most important cleaned patch piece:

- `series/0004-stavrobot-runtime-unit.patch-plan.md`

That file maps the disposable handler-local runtime helpers into the intended cleaned Shelley-side runtime unit, including:

- proposed Go types
- proposed helper function boundaries
- disposable-to-clean function mapping
- expected handler call-site shape after extraction
- suggested implementation order for the first maintained upstream patch

## First cleaned runtime prototype patch artifact

The repo now also includes a first real cleaned-runtime prototype diff captured from a managed `/opt/shelley` checkout:

- `s1-stavrobot-mode-cleaned-runtime-prototype.patch`

Current meaning of this artifact:

- it is the first concrete maintained diff that introduces a focused `server/stavrobot.go` runtime unit
- it keeps handler changes thin compared with the disposable helper-heavy shape
- it targets installer-managed bridge-profile resolution via a stable profile-state path and contract-version checks
- it now also reflects the first prototype-hardening pass that keeps the runtime result shape less text-locked by retaining raw bridge payload and leaving room for richer Shelley-native content/display adaptation later

Current limitation:

- it is still a prototype artifact, not yet the final refresh-hardened managed patch series
- the runtime file-location rule currently uses an environment-variable override plus a stable fallback path rather than a fully integrated Shelley runtime config surface
