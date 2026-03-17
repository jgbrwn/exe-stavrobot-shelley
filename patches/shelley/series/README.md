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

They are closer to apply-ready than the earlier skeleton, but should still be treated as prototype patch material until refresh/apply validation is done against a clean upstream checkout.

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
