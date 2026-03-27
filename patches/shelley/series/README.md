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

They have now also been replay/apply validated in order (`0001` → `0009`) against a fresh upstream Shelley checkout created from `/tmp/shelley-official` commit `5b07230`.

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

10. `0005-stavrobot-model-control-readonly-picker.patch`
   - read-only Stavrobot-mode model-control admin wiring
   - exposes conversation-scoped API endpoint for current provider/model + gated OpenRouter free-model list
   - surfaces compact UI status chip showing provider/model and `context_limit_display` values when available

11. `0006-stavrobot-model-control-apply-picker.patch`
   - adds Stavrobot-mode apply-action wiring on top of `0005`
   - adds conversation-scoped apply endpoint for shared backend model mutation
   - extends the compact UI chip with picker + apply button + success/error feedback

12. `0007-stavrobot-model-control-apply-safety-copy.patch`
   - adds UI-side shared-impact acknowledgement gating before apply is enabled
   - improves non-OpenRouter gating copy with explicit provider/auth requirement messaging
   - keeps the model-control UI compact while preventing accidental shared backend mutations

13. `0008-stavrobot-model-control-tests-and-contract.patch`
   - adds targeted server tests for model-control view/apply error and success paths
   - validates non-Stavrobot rejection, malformed model-control helper output handling, and apply transition response shape
   - documents model-control endpoint + UX gating contract in upstream `ARCHITECTURE.md`

14. `0009-stavrobot-model-control-notfound-hardening.patch`
   - fixes model-control 404 handling by removing fragile `sql.ErrNoRows` sentinel mapping in handlers
   - maps missing conversations to `404` using existing wrapped error text from conversation manager hydration
   - adds explicit endpoint tests for missing-conversation cases on both model-control view and apply routes

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
- even though Shelley is rich, generic raw assistant HTML/embed/audio/video should not be forced into the first Stavrobot adaptation cut unless a clearly native Shelley-safe shape is identified; sandboxed iframe/tool-style rendering and existing media-aware paths are better guides
- for image/media references specifically, a good intermediate patch-0004 step is compact `media_refs` preservation in display metadata before claiming a fuller native assistant-media mapping
- current upstream rendering uses persisted `display_data`, so the preferred follow-on is a focused Stavrobot assistant-message recording helper that can feed that native path directly while keeping debug/raw adaptation data in `user_data`

## RC handoff pass for current managed stack (`0001`..`0009`)

### Apply order (authoritative)

Apply exactly in this order:

1. `0001-metadata-sql-ui.patch`
2. `0002-conversation-manager.patch`
3. `0003-route-branching.patch`
4. `0004-stavrobot-runtime-unit.patch`
5. `0005-stavrobot-model-control-readonly-picker.patch`
6. `0006-stavrobot-model-control-apply-picker.patch`
7. `0007-stavrobot-model-control-apply-safety-copy.patch`
8. `0008-stavrobot-model-control-tests-and-contract.patch`
9. `0009-stavrobot-model-control-notfound-hardening.patch`

Do not reorder `0008` and `0009`: `0009` is intentionally incremental hardening on top of test/contract coverage added in `0008`.

### RC risk notes

- **Low-to-medium risk (server handler coupling):** `0005`/`0006`/`0009` touch handler-side routing and error mapping. Main regression surface is status-code mapping and JSON error shape for non-happy paths.
- **Low risk (UI gating UX):** `0007` is UI-only gating/copy hardening; behavior risk is mostly accidental enable/disable state logic drift.
- **Low risk (documentation/testing):** `0008` is mostly tests + contract docs; operational behavior changes are limited.
- **Known technical debt (intentional):** not-found detection currently uses wrapped error text matching (`"conversation not found"`) to align with existing handler patterns. Prefer future typed/sentinel error plumbing when touching conversation hydration boundaries again.

### Upstream handoff checklist (before applying to `/opt/shelley`)

1. Confirm upstream target ref is still intended baseline (last validated: `5b07230`).
2. Run `./validate-shelley-patch-series.sh --upstream-checkout /tmp/shelley-official --upstream-ref <target-ref>` and require full pass.
3. Verify patch apply and validation summary includes full stack through `0009`.
4. Capture final handoff note with:
   - target upstream ref
   - validator command used
   - pass/fail status
   - any local conflicts/manual offsets (should be none on validated ref)
5. Apply to managed upstream checkout (`/opt/shelley`) in the same order, then re-run upstream-local smoke/tests as required by operator policy.

### Is another doc-only patch needed before `/opt/shelley` apply?

**Current answer: no, not required.**

Rationale: current series metadata and validator now consistently cover `0001`..`0009`, and `0008` already carries the API/UX contract documentation addition in upstream `ARCHITECTURE.md`. A further doc-only patch is optional polish, not a release blocker for applying the current stack.
