# Shelley cleaned managed patch-series skeleton

## Purpose

This directory is the repo-owned skeleton for the cleaned managed Shelley S1 patch series.

It is the bridge between:

- the captured disposable diff in `../s1-stavrobot-mode-disposable-shape.patch`
- the cleanup/contract docs under `docs/`
- the eventual apply-ready maintained patch files or scripted patch applier

## Status

This directory now contains both:

- series design notes (`*.md`)
- first captured per-patch prototype diffs (`*.patch`)

The `*.patch` files are repo-owned review/apply artifacts split out of the single cleaned runtime prototype captured from `/opt/shelley`.

They have now also been replay/apply validated in order (`0001` → `0004`) against a fresh upstream Shelley checkout created from `/tmp/shelley-official` commit `5b07230`.

Current validation result:

- each patch passes `git apply --check`
- each patch applies cleanly in sequence with no ordering surprises
- the final applied tree matches the managed `/opt/shelley` prototype files for the owned Shelley surfaces
- with the normal upstream UI build prerequisite satisfied, fresh-checkout `go test ./server/... ./db/...` also passes

The repo now also includes `validate-shelley-patch-series.sh` so this replay/apply + UI-build + Go-test flow can be rerun against a chosen upstream Shelley checkout/ref.

So these are now replay/test-validated prototype patches, but not yet a fully smoke-validated final maintained patch set.

## Current series shape

1. `0001-metadata-sql-ui.md`
   - metadata structs
   - SQL update query
   - generated sqlc output ownership
   - UI type support
2. `0001-metadata-sql-ui.patch`
   - captured prototype diff for those files from `/opt/shelley`

3. `0002-conversation-manager.md`
   - conversation-manager helpers
   - per-conversation Stavrobot mapping persistence
4. `0002-conversation-manager.patch`
   - captured prototype diff for `server/convo.go`

5. `0003-route-branching.md`
   - thin handler-layer branching only
   - no profile resolution or bridge execution details in handlers
6. `0003-route-branching.patch`
   - captured prototype diff for `server/handlers.go`

7. `0004-stavrobot-runtime-unit.md`
   - focused runtime unit, conceptually `server/stavrobot.go`
   - installer-managed profile resolution
   - bridge execution
   - bridge output parsing
   - message recording / mapping persistence flow
8. `0004-stavrobot-runtime-unit.patch-plan.md`
   - function-by-function apply scaffold for converting the runtime-unit target into a maintained upstream patch
9. `0004-stavrobot-runtime-unit.patch`
   - captured prototype diff adding `server/stavrobot.go`

## Why this exists

The disposable patch already proved the seam.

The main risk now is letting the eventual maintained patch stay as one handler-heavy mixed diff.

This series skeleton reduces that risk by making the cleaned target explicit before writing the final apply-ready patch set.

## Expected next move after this skeleton

Convert these series files into one of:

- apply-ready patch files
- a scripted patch applier
- direct implementation against a managed Shelley checkout under `/opt/shelley`

The most likely next technical step is implementing patch 4 first in a focused Shelley-side runtime file while keeping patch 3 thin.

## Current review conclusions from the captured split

- `0001` and `0002` are already very close to the intended final managed shape.
- `0003` is cleanly thin and now depends on the runtime entrypoint rather than handler-local Stavrobot helpers.
- `0004` is the main prototype/runtime patch and the main remaining place for refinement.

## S2 / rich-output reminder

S1 remains intentionally text-first.

But patch `0004` should continue to be reviewed against the explicit longer-term goal that the Shelley-facing runtime layer must eventually preserve or pass through richer Shelley-native content semantics when the bridge grows structured output support.

That means the current `server/stavrobot.go` shape is acceptable for S1, but should not be treated as proof that the final runtime boundary is permanently text-only.

The preferred widening references are now:

- `../../../docs/SHELLEY_S2_STRUCTURED_BRIDGE_TARGET.md`
- `../../../docs/SHELLEY_RUNTIME_ADAPTATION_CONTRACT.md`

Those docs together define:

- the narrow first S2 bridge payload target
- the preferred `StavrobotTurnResult` widening path
- the fallback rule that `ResponseText` remains mandatory even as richer adaptation lands
- and, now, the bridge/runtime alignment rule that patch `0004` should normalize the canonical bridge fields that already exist in practice today: `content`, compact `display.tool_summary`, and `raw`


## Current patch-0004 review notes

A quick review of upstream Shelley's current `llm.Content` model shows that Shelley already has more structure than plain text alone, including tool-use/result and display-oriented fields.

So while the current prototype `0004` patch is acceptable for S1, its helper/result shapes should continue to be reviewed as temporary text-first simplifications rather than as the final long-term Shelley↔Stavrobot content boundary.


## Additional UI preservation rule

All Shelley-side Stavrobot integration work should preserve upstream Shelley's existing excellent mobile/responsive presentation.

So even future richer-output work should prefer native Shelley content/display mapping over any separate Stavrobot-specific rendering path.

Practically, future sessions should treat this as a review rule for patch `0004` and later follow-ons:

- compact display metadata is preferred over large custom Stavrobot panels
- existing Shelley message/content surfaces should be preferred over bespoke layouts
- richer output should still degrade cleanly to ordinary assistant content when necessary
