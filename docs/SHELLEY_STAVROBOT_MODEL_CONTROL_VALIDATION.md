# Shelley Stavrobot model control validation

## Purpose

Turn the earlier feasibility review into an operational validation artifact.

This document records what was actually validated about changing the Stavrobot backend model behind Shelley, with emphasis on the key implementation question:

- does changing the Stavrobot model require a full rebuild, or only config mutation plus service restart/recreate?

## Scope of validation

Validation was done against the disposable local Stavrobot test bed:

- repo: `/tmp/stavrobot`
- local endpoint: `http://localhost:8000`
- config file: `/tmp/stavrobot/data/main/config.toml`

This was treated as disposable runtime validation, not production rollout.

## Key validated findings

## 1. Stavrobot model selection is loaded from `config.toml`

Observed current live config shape:

```toml
provider = "openrouter"
model = "z-ai/glm-4.5-air:free"
```

Code inspection in `/tmp/stavrobot` confirmed:

- `src/config.ts` loads `provider` and `model` from TOML at startup
- `src/agent.ts` calls `getModel(config.provider, config.model)` during agent creation
- Docker mounts `./data/main` into the app container as `/app/config`
- `CONFIG_PATH` for the app container is `/app/config/config.toml`

Implication:

- model choice is startup/runtime config, not an image-build constant

## 2. Full image rebuild was **not** required for the tested model change

This was the most important result.

Validated mutation sequence:

1. change only the `model = ...` line in `/tmp/stavrobot/data/main/config.toml`
2. run:

```bash
cd /tmp/stavrobot
docker compose restart app
```

3. re-check health
4. send a real chat request

Result:

- Stavrobot came back healthy
- health endpoint reported the new model
- real chat requests succeeded

Implication:

- for this validated case, model control should target **config mutation + app restart**
- it should **not** be framed primarily as a Shelley rebuild feature
- it likely does **not** require `docker compose up --build` for simple model changes

## 3. Health endpoint reflected the new model after restart

Before mutation, validated response included:

```json
{
  "ok": true,
  "provider": "openrouter",
  "model": "z-ai/glm-4.5-air:free"
}
```

After changing config to `openrouter/free` and restarting `app`, validated response included:

```json
{
  "ok": true,
  "provider": "openrouter",
  "model": "openrouter/free"
}
```

This gives a straightforward post-apply verification mechanism for a future helper/UI flow.

## 4. `openrouter/free` worked in a basic live test

Validated live behavior after switching to:

```toml
model = "openrouter/free"
```

Observed:

- health reported `openrouter/free`
- a first chat request succeeded
- a continuation turn on the same `conversation_id` also succeeded

So `openrouter/free` is not merely theoretical anymore. It passed a basic runtime test in the disposable stack.

## Important caveat on response quality

One first-turn response through `openrouter/free` returned the requested exact text twice:

- `postchange-openrouter-free-ok`
- followed by the same line again

A second-turn continuation test returned the exact requested single-line reply.

Implication:

- `openrouter/free` is usable enough to keep on the candidate list
- but it should still be treated as a **validation-needed option**, not automatically the preferred default
- extra prompt/behavior testing would be useful before promoting it strongly in UI

## 5. Restoring the previous model was also straightforward

Validated rollback path:

1. change `model` back to `z-ai/glm-4.5-air:free`
2. run `docker compose restart app`
3. re-check health

Result:

- Stavrobot returned healthy on the prior model again

Implication:

- rollback can likely use the same control path as apply

## Recommended implementation consequence

## This should be treated as Stavrobot runtime admin control, not Shelley rebuild control

The validated path does **not** point to:

- rebuild Shelley
- rebuild Stavrobot images
- regenerate broad local integration state

Instead it points to a narrower operational flow:

1. fetch candidate models
2. inspect current configured model
3. update Stavrobot config file
4. restart or recreate the app service
5. check readiness/health
6. report success/failure

That means the feature belongs in a **Stavrobot-mode-only admin/operator surface** in Shelley, backed by a controlled local helper/service.

## Recommended first operational command shape

A future helper should probably do something equivalent to:

### Read current

```bash
./manage-stavrobot-model.sh get-current
```

### List candidates

```bash
./manage-stavrobot-model.sh list-openrouter-free
```

### Apply model

```bash
./manage-stavrobot-model.sh apply --model openrouter/free
```

Where `apply` should roughly perform:

1. validate requested model ID
2. edit `config.toml`
3. restart `app` service
4. poll health until ready or timeout
5. return JSON status with previous/current model

## Restart vs recreate vs build recommendation

Based on current validation:

### Preferred first implementation target

- `config.toml` mutation
- `docker compose restart app`
- health check polling

### Fallback if restart proves insufficient in some environments

- `docker compose up -d --force-recreate app`

### Only use build if later validation proves necessary

- `docker compose up -d --build --force-recreate app`

Current evidence supports **restart-first**, not build-first.

## Suggested UI implication for Shelley

If this feature is later exposed in Shelley, the wording should emphasize:

- available only in Stavrobot mode context
- changes the shared Stavrobot backend model
- may briefly interrupt active Stavrobot requests
- usually applies via backend restart, not full rebuild

That is a much better user expectation than saying "rebuild Stavrobot" for a model-only change.

## Open questions still worth validating later

1. is `restart app` always sufficient, or do some config/provider changes require recreate?
2. does changing `provider` as well as `model` still work with restart-only?
3. should helper write a backup of prior config before mutation?
4. should helper run a post-apply test chat in addition to health?
5. how stable is `openrouter/free` over repeated tests, especially for exact-output prompts and tool-heavy behavior?
6. what happens to in-flight Stavrobot requests during restart from a live Shelley session?

## Final recommendation

The validated operational path is:

- **change model in Stavrobot config**
- **restart the Stavrobot app service**
- **verify health**

So future Shelley-side Stavrobot model control should be designed around a **controlled runtime mutation helper**, not around a Shelley rebuild flow.

## Recommended next artifact after this validation

If we pursue the feature, the next useful artifact should be a concrete helper contract/recipe, e.g.:

- exact helper CLI and JSON responses
- exact config edit method
- exact health polling logic
- exact rollback behavior
- privilege model for safe invocation from Shelley
