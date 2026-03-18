# Shelley strategic gap audit

## Purpose

Capture the current post-S1/operator state of the Shelley/Stavrobot work so the next implementation steps stay grounded in what is already validated versus what is still open.

This audit focuses on the remaining strategic areas after the managed rebuild/status/operator-helper work was tightened:

- richer Shelley-native display/content fidelity
- cross-conversation memory/recall behavior
- Shelley-native backend model-control UX placement
- preservation of upstream Shelley mobile/responsive quality

## Current baseline

What is already in good shape:

- installer-managed Shelley rebuild/status flow exists
- managed rebuild provenance and dirty-checkout warning behavior exist
- bridge-profile contract and helper exist
- canonical Shelley-facing bridge exists
- operator-facing Stavrobot backend model helper now exists and is lightly regression-covered
- S1 seam is validated: optional per-conversation Stavrobot mode above Shelley's normal model/provider layer

What that means:

- the project is no longer blocked on basic helper/status plumbing
- the next work should avoid reopening settled operator mechanics unless required by a later phase
- remaining gaps are primarily Shelley-side product/integration fidelity questions

## Gap 1: richer Shelley-native display/content mapping

## Status

This is still open.

The docs consistently point to S2 as the next Shelley-facing fidelity phase:

- bridge output should evolve beyond text-only when useful
- Shelley should map richer bridge results into its native message/content/display structures
- the runtime/adaptation boundary in `server/stavrobot.go` should not freeze the design into a permanent plain-text tunnel

## What is already decided

- Shelley should not treat Stavrobot as merely another plain model provider
- Shelley should continue to shell out only to the canonical bridge
- richer output should be adapted into Shelley-native surfaces rather than a parallel Stavrobot-only UI
- markdown/media/tool/display fidelity should improve through Shelley's own content model

## Main open questions

1. What exact structured bridge contract should be considered stable enough for S2?
2. Which Shelley's native content/display primitives should be targeted first?
3. Which rich artifacts should be supported first:
   - markdown cleanliness
   - tool/event summaries
   - image/screenshot/media references
   - HTML-safe structured content blocks
4. Which unsupported result shapes should still degrade cleanly to text in S2?

## Recommended next concrete work for this gap

1. Define a small S2 bridge payload extension document.
2. Pick only 2-3 first-class adaptation targets for the first increment:
   - markdown-preserving assistant text
   - tool/event summary display
   - image/media reference mapping if the bridge can supply it cleanly
3. Keep text fallback mandatory for every richer shape.
4. Implement at the adaptation boundary rather than adding Stavrobot-specific rendering paths throughout the UI.

## Implementation guardrails

- do not bypass the canonical bridge contract
- do not build a separate Stavrobot-only thread renderer
- do not regress ordinary Shelley rendering paths
- keep unsupported structured content explicitly classified rather than silently flattened

## Gap 2: cross-conversation memory / recall

## Status

Still unresolved by design.

The current docs consistently recommend validation before architecture expansion.

## What is already decided

- per-conversation Shelley↔Stavrobot mapping solves active-thread continuity, not global recall by itself
- cross-conversation recall should be treated as separate from the active mapping
- Shelley should not assume it needs its own retrieval layer before testing Stavrobot-native behavior more deeply
- if explicit retrieval is later needed, it should be legible to the user rather than appearing magical

## Main open questions

1. Does Stavrobot already answer realistic cross-conversation prompts well enough without extra Shelley orchestration?
2. Are failures systemic or only occasional edge cases?
3. Is long-lived single-thread continuity already sufficient for many practical operator workflows?
4. If explicit retrieval is needed later, what minimum UX makes that visible and understandable?

## Recommended next concrete work for this gap

1. Run the S4 validation checklist already described in `docs/SHELLEY_STAVROBOT_MVP.md`.
2. Record results from a small real-world prompt matrix covering:
   - same-thread long-lived recall
   - cross-thread recall
   - time-separated work
   - tool/event-heavy histories
3. Make a deliberate fork decision only after those observations:
   - S4A: no major Shelley retrieval layer yet
   - S4B: explicit Shelley-side retrieval/reconciliation layer

## Implementation guardrails

- do not put cross-conversation memory state into per-conversation mapping metadata
- do not market retrieval as native memory if a separate search/reconciliation pass was required
- do not build retrieval machinery before collecting evidence that it is needed

## Gap 3: Shelley-native backend model-control UX

## Status

Helper boundary exists; Shelley UI integration does not.

## What is already decided

- this feature should be Stavrobot-mode-only
- it controls the shared local Stavrobot backend, not per-conversation state
- it should be layered on top of `manage-stavrobot-model.sh` or an equivalent narrow local helper/service boundary
- OpenRouter choices should surface only when Stavrobot is actually configured for OpenRouter with corresponding auth/config

## Recommended next concrete work for this gap

Short term:

- keep current operator-helper-only posture
- avoid mixing shared-backend model mutation into the main installer flow

Later Shelley work:

- place this in a compact Stavrobot-mode admin/backend area
- make shared-impact wording explicit
- keep the control out of normal upstream Shelley model/provider selection UI

## Implementation guardrails

- do not imply model choice is per-conversation unless Stavrobot later supports that natively
- do not grant Shelley broad arbitrary docker/sudo access
- do not surface OpenRouter picker when current provider/auth state does not justify it

## Gap 4: mobile / responsive UI preservation

## Status

This is an explicit non-functional requirement, not an optional polish item.

The current docs are consistent:

- preserve upstream Shelley's strong mobile/responsive presentation
- keep Stavrobot-specific controls compact and conversation-scoped
- avoid parallel Stavrobot-specific layouts that could drift from upstream behavior

## Recommended next concrete work for this gap

1. Treat responsive impact as a first-class review criterion for every Shelley patch.
2. Keep the first Stavrobot-specific UI additions limited to:
   - compact mode badge/state
   - compact context label
   - compact degraded-state recovery affordances
   - compact admin/backend controls only inside Stavrobot mode context
3. Prefer using existing Shelley message/content components instead of new layout systems.
4. Add mobile screenshot/manual checks to future Shelley UI validation runs when managed rebuild work advances beyond S1.

## Implementation guardrails

- do not expand the composer/header into a dense Stavrobot dashboard
- do not create desktop-only Stavrobot controls that break narrow layouts
- do not fork upstream Shelley interaction patterns without a strong reason

## Priority recommendation

Recommended order from here:

1. **S2 prep and scope cut**
   - write the minimal structured-output/adaptation target for Shelley-native fidelity
2. **S4 evidence gathering**
   - run the cross-conversation recall validation matrix and record results
3. **later Shelley UI work**
   - only after S2/S4 prep, decide whether backend-model control belongs in the first Shelley admin surface or stays operator-only for longer

## Short execution summary

The repo is now past the stage where the main risk is helper/installer drift.

The main remaining risk is building the next Shelley increments without enough product discipline.

So the near-term emphasis should be:

- choose a narrow S2 rich-output target
- validate S4 recall behavior with evidence
- preserve upstream Shelley UI/mobile strengths while integrating Stavrobot through native Shelley surfaces
