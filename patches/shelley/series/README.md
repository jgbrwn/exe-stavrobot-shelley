# Shelley cleaned managed patch-series skeleton

## Purpose

This directory is the repo-owned skeleton for the cleaned managed Shelley S1 patch series.

It is the bridge between:

- the captured disposable diff in `../s1-stavrobot-mode-disposable-shape.patch`
- the cleanup/contract docs under `docs/`
- the eventual apply-ready maintained patch files or scripted patch applier

## Status

These files are not yet apply-ready patch files.

They are the first concrete maintained split of the future cleaned patch by concern, so the next implementation step can work patch-by-patch instead of re-reading the whole disposable diff.

## Current series shape

1. `0001-metadata-sql-ui.md`
   - metadata structs
   - SQL update query
   - generated sqlc output ownership
   - UI type support

2. `0002-conversation-manager.md`
   - conversation-manager helpers
   - per-conversation Stavrobot mapping persistence

3. `0003-route-branching.md`
   - thin handler-layer branching only
   - no profile resolution or bridge execution details in handlers

4. `0004-stavrobot-runtime-unit.md`
   - focused runtime unit, conceptually `server/stavrobot.go`
   - installer-managed profile resolution
   - bridge execution
   - bridge output parsing
   - message recording / mapping persistence flow

5. `0004-stavrobot-runtime-unit.patch-plan.md`
   - function-by-function apply scaffold for converting the runtime-unit target into a maintained upstream patch

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
