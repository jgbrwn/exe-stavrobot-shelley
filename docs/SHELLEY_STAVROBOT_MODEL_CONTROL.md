# Shelley Stavrobot model control review

## Purpose

Review whether Shelley should let the user inspect and change the **Stavrobot backend model** from the Shelley interface, while preserving the core design rule:

- Shelley should behave exactly like upstream unless the user explicitly selects **Stavrobot mode**

This document treats model control as a **Stavrobot-mode-only operator feature**, not a global change to ordinary upstream Shelley behavior.

## Bottom line

Yes, this is feasible.

But it should be implemented as:

- a **Stavrobot-mode-aware operator/admin control** in Shelley
- backed by an **installer-managed local helper/service**
- affecting the **shared Stavrobot backend configuration**

It should **not** be implemented as:

- part of the ordinary per-turn chat bridge path
- a fake per-conversation model picker if the underlying change is really global
- blanket direct sudo/docker access from arbitrary Shelley runtime paths

## Critical scope rule

This feature only exists when Shelley is operating in **Stavrobot mode**.

That means:

- upstream Shelley behavior stays unchanged when Stavrobot mode is off
- normal non-Stavrobot conversations should not gain unrelated backend-management controls
- model control should be hidden, disabled, or absent outside Stavrobot mode
- the OpenRouter-backed model picker should only surface when the active Stavrobot config is actually using `provider = "openrouter"` with valid corresponding auth/config

This matches the project’s current philosophy:

- optional per-conversation Stavrobot mode
- preserve normal Shelley behavior otherwise

## What exactly is being controlled?

The proposal is to let Shelley:

1. show the current model used by the local Stavrobot backend
2. fetch and display candidate OpenRouter free models live
3. allow selection of one of those models
4. apply the change to the Stavrobot backend
5. restart/recreate/rebuild whatever is required
6. report success/failure/readiness back in Shelley UI

Also of interest:

- include `openrouter/free` as a selectable router-style option
- validate later whether `openrouter/free` behaves well enough in Stavrobot practice

## Feasibility assessment

### 1. Live model list in Shelley

Feasible.

This repo already has reusable logic in:

- `py/openrouter_models.py`

That script already:

- fetches `https://openrouter.ai/api/v1/models`
- filters zero-cost models
- returns structured JSON
- includes curated preference ordering
- includes `openrouter/free`

So the basic model-inventory behavior is already validated locally.

### 2. Applying a chosen model to Stavrobot

Feasible.

The main questions are operational, not conceptual:

- which exact config field(s) must change
- whether model changes need restart, recreate, or full build
- how to validate readiness after the change
- how to expose this safely to Shelley

### 3. Shelley triggering docker compose or service actions

Feasible, but the privilege boundary matters.

Technically possible approaches:

- Shelley invokes a tightly scoped helper script
- Shelley talks to a local admin service which owns the privileged action
- Shelley directly shells out to privileged commands

Only the first two are good candidates.

## Most important design distinction

This is **not** the same thing as per-conversation Stavrobot routing.

Per-conversation Stavrobot mode is about:

- how a specific Shelley conversation is handled
- which remote Stavrobot conversation it maps to
- how the bridge is invoked for that thread

Model control is about:

- machine-local shared Stavrobot backend config
- provider/model discovery
- restart/recreate/build lifecycle
- possible effect on many Stavrobot-mode conversations

So these should remain separate concepts in the implementation.

## UX recommendation

## Do not present this as a per-conversation model picker

Unless Stavrobot later supports true per-conversation model selection, a Shelley UI control that looks conversation-local would be misleading.

Why:

- the current likely effect is global/shared backend mutation
- changing the model may affect all Stavrobot-mode conversations
- active requests may be interrupted

So the recommended framing is:

- **Stavrobot backend model**
- **Applies to the shared local Stavrobot backend**
- **Available only from Stavrobot mode context**

## Recommended UI placement

Best current fit:

- show only when the current conversation is in Stavrobot mode
- treat it as a **Stavrobot mode backend/admin panel** or action area
- not part of normal upstream Shelley model/provider selection UI

Possible UI elements:

- current backend provider/model
- last refresh time for model catalog
- refresh model list action
- candidate models list
- highlight current active model
- warning that apply affects shared Stavrobot backend
- apply action
- progress/readiness state
- revert-to-previous action later

## Recommended wording

Examples:

- `Stavrobot backend model`
- `Applies to the shared Stavrobot backend`
- `Changing this may restart or recreate the Stavrobot service`
- `Available only for Stavrobot-mode conversations`

## Recommended implementation boundary

## Shelley should not directly own broad privileged docker access

Avoid:

- giving Shelley blanket sudo over docker compose
- letting arbitrary Shelley runtime flows mutate config directly
- mixing normal conversation execution with machine-admin side effects

## Preferred pattern: controlled helper

Recommended shape:

- Shelley calls a dedicated local helper such as `manage-stavrobot-model.sh`
- helper validates requested action/model
- helper mutates Stavrobot config safely
- helper runs the required restart/recreate/build path
- helper waits for readiness
- helper returns machine-readable JSON status

This helper can be:

- directly executable if permissions allow
- or the only command permitted by sudoers

This is far safer than broad direct docker access.

## Possible better long-term pattern: local admin service

If later admin actions expand, a local admin service may be cleaner.

Possible future admin actions:

- fetch model catalog
- inspect current provider/model
- change model
- restart Stavrobot
- inspect health
- show current bridge profiles
- maybe switch provider later

But a helper script is enough for an initial implementation.

## State ownership recommendation

## Do not store selected backend model in conversation metadata

Current recommendation:

- keep conversation metadata focused on per-conversation mode/routing state
- keep shared backend model config in installer-managed local state or in Stavrobot config itself

Why:

- backend model choice is machine-global/shared state
- conversation metadata should stay small and semantically correct
- otherwise the UI would imply a false per-conversation guarantee

## Suggested installer-managed state additions

This feature suggests one more small state area beyond the rebuild contract.

Possible file:

- `state/stavrobot-runtime-state.json`

Potential contents:

```json
{
  "schema_version": 1,
  "provider": "openrouter",
  "model": "openrouter/free",
  "source": "config.toml",
  "catalog": {
    "source": "openrouter-free",
    "fetched_at": "2025-01-01T00:00:00Z"
  },
  "last_change": {
    "applied_at": "2025-01-01T00:00:00Z",
    "previous_model": "z-ai/glm-4.5-air:free",
    "result": "ok"
  }
}
```

That is optional, but useful if Shelley later wants to show:

- current configured model
- when it was last changed
- previous model for rollback hints

## Source of model list

Best source for a first implementation:

- reuse or wrap `py/openrouter_models.py`

Benefits:

- consistent with installer behavior
- no duplicated free-model filtering logic
- existing curated preference ordering already present
- `openrouter/free` already included

## Important validation question: does model change require rebuild?

This should be tested directly before implementation assumptions harden.

Likely possibilities:

### Best case

- config update only
- container restart or recreate
- no image rebuild needed

### Acceptable case

- config update
- `docker compose up -d --force-recreate`

### Heavier case

- config update
- `docker compose up -d --build --force-recreate`

My current expectation is that a pure model change should usually be **restart/recreate**, not full image rebuild.

That matters for UX because:

- `restart backend` sounds reasonable
- `full rebuild` sounds slower and more disruptive

So this should be validated before finalizing the Shelley-side wording.

## Operational concerns

### Shared impact

Because this likely changes shared backend state:

- active Stavrobot-mode conversations may be affected
- in-flight requests may fail or be interrupted
- temporary readiness loss is expected during apply

So the UI should say this clearly.

### Readiness feedback

Shelley should not just fire-and-forget.

It should show:

- applying change
- restarting/recreating/building
- ready again
- failed with actionable reason if possible

### Rollback

Later hardening should support:

- previous model visibility
- one-click revert or operator-guided revert
- clear failure report if new model does not work

## Recommended phased implementation

## M1: inspect-only

Add a Stavrobot-mode-only UI/control that can:

- show current backend provider/model
- fetch/show live OpenRouter free models
- show `openrouter/free`
- not mutate anything yet

Why first:

- low risk
- validates usefulness
- validates operator framing
- no privilege change required yet beyond read access

## M2: controlled apply

Add the ability to:

- select a model
- invoke controlled local helper
- update config
- restart/recreate backend
- wait for readiness
- report result

## M3: hardening

Add:

- previous model / rollback support
- clearer event/log reporting
- optional health/test prompt after apply
- maybe provider switching later if desired

## Recommended local helper contract

A first helper could expose actions like:

```bash
./manage-stavrobot-model.sh get-current
./manage-stavrobot-model.sh list-openrouter-free
./manage-stavrobot-model.sh apply --model openrouter/free
```

Recommended output:

- JSON by default
- machine-readable status/result fields
- explicit exit status on failure

Example response shapes:

```json
{
  "provider": "openrouter",
  "model": "z-ai/glm-4.5-air:free"
}
```

```json
{
  "source": "openrouter-free",
  "models": [
    {"id": "openrouter/free", "name": "OpenRouter Free Router"}
  ]
}
```

```json
{
  "status": "ok",
  "previous_model": "z-ai/glm-4.5-air:free",
  "current_model": "openrouter/free",
  "operation": "recreate",
  "ready": true
}
```

## Privilege model recommendation

If privilege is needed, prefer one of:

### Narrow sudoers allowance

Allow the Shelley-running user to execute only the dedicated helper.

Not:

- arbitrary shell
- arbitrary docker compose commands
- arbitrary config edits

### Or system service boundary

A local service can own privileged operations and Shelley can call it via localhost.

For initial implementation, narrow-helper is probably enough.

## Relationship to current Shelley rebuild plan

This feature should be treated as a **parallel Stavrobot-mode admin surface**, not a prerequisite for S1 routing itself.

That means:

- do not block the managed S1 rebuild recipe on this feature
- but do account for it in the rebuild architecture so it has a clean home later

Specifically, the future Shelley rebuild can reserve space for:

- a Stavrobot-mode-only backend/admin panel
- read-only current backend status
- future controlled model-change action

without making it part of ordinary upstream Shelley behavior.

## `openrouter/free` specific note

Including `openrouter/free` in the candidate list is reasonable.

But before presenting it as a preferred default, validate:

- normal chat quality in Stavrobot
- continuity behavior across multiple turns
- compatibility with any tool/event assumptions
- whether rate limits or routing behavior make it too unstable for default recommendation

So it should be included for testing, but not blindly promoted before validation.

## Final recommendation

Yes, pursue this idea.

But keep these boundaries:

1. **Stavrobot-mode-only feature**
2. **shared backend/admin control, not fake per-conversation model state**
3. **controlled helper/service boundary for privileged actions**
4. **reuse existing OpenRouter model-fetch logic from this repo**
5. **validate restart vs recreate vs rebuild before final UX wording**

## Best next artifact after this review

If this direction is accepted, the next practical artifact should be a small operational recipe for validating the runtime mutation path:

- current config field for Stavrobot model
- exact edit mechanism
- exact docker compose/service command actually needed
- readiness check sequence
- whether `openrouter/free` works cleanly in practice

That would turn this from feasibility review into a concrete implementation/testing plan.


## Validation update

A concrete disposable runtime validation now exists in:

- `docs/SHELLEY_STAVROBOT_MODEL_CONTROL_VALIDATION.md`

Most important validated result:

- for a tested OpenRouter model change, Stavrobot did **not** require a full rebuild
- changing `model` in `config.toml` plus `docker compose restart app` was enough
- `openrouter/free` also passed a basic live first-turn and continuation check

That means future Shelley-side model control should be framed as a **runtime config mutation + restart/recreate** feature, not primarily as a rebuild flow.
