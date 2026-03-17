# Shelley Stavrobot model control helper contract

## Purpose

Define the concrete local helper contract for future Shelley-triggered Stavrobot backend model control.

This document turns prior review + runtime validation into an actionable implementation target.

It assumes the already validated conclusion that:

- Stavrobot model control should be treated as **runtime config mutation + restart/recreate**
- not as a Shelley rebuild path

## Scope

This helper contract is for a future feature that is:

- available only from **Stavrobot mode** context in Shelley
- limited to **shared Stavrobot backend model control**
- implemented through a **controlled local helper boundary**

It is not for:

- ordinary upstream Shelley behavior
- per-conversation backend model state
- arbitrary system administration from Shelley

## Governing UI rule

The OpenRouter-backed model picker should surface only when Stavrobot is actually configured to use OpenRouter.

Minimum expected gating condition:

- `provider = "openrouter"` in active Stavrobot config
- and at least one valid OpenRouter auth path is configured (`apiKey` or `authFile` according to Stavrobot rules)

If those conditions are not met, Shelley should:

- hide the OpenRouter model picker
- or show a disabled control with explanatory text

Suggested wording:

- `OpenRouter model selection is available only when Stavrobot is configured with provider = openrouter.`

## High-level architecture

Recommended flow:

1. Shelley conversation is in **Stavrobot mode**
2. Shelley shows a Stavrobot backend/admin control area
3. Shelley asks local helper for:
   - current provider/model
   - whether OpenRouter model selection is available
   - live OpenRouter free-model list when applicable
4. user selects a model
5. Shelley calls helper `apply`
6. helper edits Stavrobot config and restarts/recreates app service
7. helper polls health and returns machine-readable result
8. Shelley shows success/failure/current model

## Helper location and invocation

Proposed local helper name:

- `manage-stavrobot-model.sh`

Likely location in this repo later:

- `/home/exedev/exe-stavrobot-shelley/manage-stavrobot-model.sh`

Shelley should treat this helper as the local contract for model control.

## Privilege model

Preferred rule:

- Shelley should not get broad direct sudo/docker access
- Shelley should only be allowed to invoke the dedicated helper

The helper may itself:

- run directly if permissions already allow required operations
- or be the only command whitelisted via sudoers

Allowed outcome:

- narrow privilege for one controlled entrypoint

Disallowed outcome:

- arbitrary shell
- arbitrary docker compose commands
- arbitrary config writes unrelated to this feature

## Required helper actions

Initial minimum CLI:

```bash
./manage-stavrobot-model.sh get-current
./manage-stavrobot-model.sh list-openrouter-free
./manage-stavrobot-model.sh apply --model MODEL_ID
```

Later possible actions:

```bash
./manage-stavrobot-model.sh verify
./manage-stavrobot-model.sh rollback
```

## Required config inputs

The helper must know how to locate the active Stavrobot config and stack.

Recommended explicit flags:

- `--stavrobot-dir /path/to/stavrobot`
- optional `--config-path /path/to/config.toml`
- optional `--base-url http://localhost:8000`
- optional `--timeout SECONDS`

Recommended defaulting rules:

1. if `--config-path` supplied, use it
2. else use `--stavrobot-dir/data/main/config.toml`
3. base URL defaults to local configured stack URL when known
4. helper should fail clearly if required paths do not exist

## Action: `get-current`

Purpose:

- inspect current backend configuration and whether OpenRouter model control should be surfaced

### Responsibilities

- read active Stavrobot config
- parse current `provider`
- parse current `model`
- detect whether OpenRouter model picker is applicable
- optionally read current live health result

### Example output

```json
{
  "status": "ok",
  "provider": "openrouter",
  "model": "z-ai/glm-4.5-air:free",
  "openrouter_model_selection_available": true,
  "auth_mode": "apiKey",
  "health": {
    "ok": true,
    "provider": "openrouter",
    "model": "z-ai/glm-4.5-air:free"
  }
}
```

### Example when not applicable

```json
{
  "status": "ok",
  "provider": "anthropic",
  "model": "claude-sonnet-4-20250514",
  "openrouter_model_selection_available": false,
  "reason": "provider_is_not_openrouter"
}
```

## Action: `list-openrouter-free`

Purpose:

- return live candidate OpenRouter free models for UI selection

### Gating rule

This action should succeed only when OpenRouter model control is applicable.

If not applicable, it should return a clear machine-readable refusal.

### Responsibilities

- read current config first
- confirm `provider = "openrouter"`
- confirm auth/config is sufficient for OpenRouter-backed operation
- reuse this repo's existing OpenRouter model fetch/filter logic
- return structured model list
- include `openrouter/free`

### Recommended implementation source

Reuse or wrap:

- `py/openrouter_models.py`

Do not duplicate the filtering/sorting logic in multiple places unless necessary.

### Example success output

```json
{
  "status": "ok",
  "source": "openrouter-free",
  "provider": "openrouter",
  "models": [
    {
      "id": "openrouter/free",
      "name": "Free Models Router",
      "context_length": 200000
    },
    {
      "id": "qwen/qwen3-coder:free",
      "name": "Qwen: Qwen3 Coder 480B A35B (free)",
      "context_length": 262000
    }
  ]
}
```

### Example gated refusal

```json
{
  "status": "error",
  "error": "openrouter_not_active",
  "message": "OpenRouter model selection is unavailable because Stavrobot is not currently configured with provider = openrouter."
}
```

## Action: `apply --model MODEL_ID`

Purpose:

- change the shared Stavrobot backend model and bring the runtime back to healthy state

### Preconditions

- current config must indicate `provider = "openrouter"`
- requested model string must be non-empty
- helper should validate the requested model against live candidate list or explicit allow policy

### Responsibilities

1. read current config
2. verify OpenRouter model control is applicable
3. store current model as `previous_model`
4. edit only the `model` field in config
5. restart or recreate Stavrobot app service
6. poll health endpoint until success or timeout
7. confirm reported model matches requested model
8. return JSON result

### Preferred operation order

#### First attempt

- mutate config
- `docker compose restart app`
- poll health

#### Fallback if restart is insufficient

- `docker compose up -d --force-recreate app`
- poll health again

#### Build path

Do not use build by default for model-only changes.

Only escalate later if broader validation proves it necessary.

### Example success output

```json
{
  "status": "ok",
  "operation": "restart",
  "previous_model": "z-ai/glm-4.5-air:free",
  "current_model": "openrouter/free",
  "provider": "openrouter",
  "ready": true,
  "health": {
    "ok": true,
    "provider": "openrouter",
    "model": "openrouter/free"
  }
}
```

### Example success with recreate fallback

```json
{
  "status": "ok",
  "operation": "force-recreate",
  "previous_model": "z-ai/glm-4.5-air:free",
  "current_model": "openrouter/free",
  "provider": "openrouter",
  "ready": true,
  "health": {
    "ok": true,
    "provider": "openrouter",
    "model": "openrouter/free"
  }
}
```

### Example failure output

```json
{
  "status": "error",
  "error": "apply_failed",
  "previous_model": "z-ai/glm-4.5-air:free",
  "attempted_model": "openrouter/free",
  "operation": "restart",
  "ready": false,
  "message": "Timed out waiting for Stavrobot health after model change."
}
```

## Config mutation requirements

The helper should mutate only the top-level `model` field in active `config.toml`.

Rules:

- preserve all unrelated config
- avoid exposing secrets in logs/output
- prefer atomic write pattern if practical
- preserve a rollback path to previous model value

Recommended implementation strategy:

- parse TOML via a controlled helper script or Python helper
- write updated file atomically
- avoid brittle raw `sed` mutation if a safer parser-based edit is practical

## Health polling requirements

After `apply`, helper should poll the validated client health path until:

- `ok == true`
- `provider` matches expected provider
- `model` matches requested model

Recommended timeout behavior:

- configurable timeout
- short poll interval
- explicit timeout error on failure

## Rollback recommendation

A full rollback command is optional for first implementation, but helper should at least:

- remember `previous_model` during apply
- report it in output
- avoid leaving the operator blind

Future `rollback` action could:

- restore previous model
- restart/recreate app
- verify health

## UI semantics for Shelley

Shelley should treat helper outputs as operator/admin results, not conversation content.

Recommended UI behavior:

- show current model only in Stavrobot mode context
- only show OpenRouter picker when `openrouter_model_selection_available == true`
- show shared-impact warning before apply
- show progress state during apply
- show final current model and readiness

Suggested warning:

- `This changes the shared Stavrobot backend model and may briefly interrupt active Stavrobot requests.`

## Error taxonomy recommendation

Helper should return machine-readable error IDs such as:

- `openrouter_not_active`
- `missing_config`
- `invalid_model`
- `config_write_failed`
- `restart_failed`
- `health_timeout`
- `health_mismatch`
- `auth_not_configured`

This will let Shelley present useful operator-facing errors without parsing raw stderr.

## Logging recommendations

Helper logs should:

- avoid printing secrets
- identify requested model
- identify operation used (`restart` vs `force-recreate`)
- record timeout/failure cause clearly

Helper JSON response should stay concise and machine-oriented.

## `openrouter/free` interpretation note

A duplicate exact-text response was observed during one disposable validation after switching to `openrouter/free`.

That observation should be recorded conservatively:

- it is an observed behavior with **unclear cause**
- it should not yet be treated as proof of an `openrouter/free`-specific defect
- the cause could be model behavior, prompting, runtime behavior, or some unrelated issue

So the helper contract should continue to allow `openrouter/free` as a candidate option.

## Relationship to current docs

This contract builds on:

- `docs/SHELLEY_STAVROBOT_MODEL_CONTROL.md`
- `docs/SHELLEY_STAVROBOT_MODEL_CONTROL_VALIDATION.md`

Most important carried-forward conclusions:

- model control is Stavrobot-mode-only
- model control is runtime admin control, not Shelley rebuild control
- OpenRouter picker should be gated by actual active OpenRouter config
- restart-first is the right initial apply strategy

## Recommended next implementation step

After this contract, the next practical step would be to implement a disposable local helper in this repo and validate:

1. parser-safe `config.toml` mutation
2. restart-first apply flow
3. fallback recreate flow
4. machine-readable error handling
5. Shelley-facing status semantics
