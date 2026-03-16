# Implementation plan

## Goal

Build a standalone, Bash-first installer for Stavrobot on exe.dev VMs. The installer must be deterministic, idempotent where practical, and must not depend on Stavrobot's LLM to complete setup.

## Core decisions

1. Keep this installer in a separate repo from the upstream Stavrobot clone.
2. Use Bash for orchestration and Python for structured parsing/rendering.
3. Generate clean `.env` and `data/main/config.toml` files rather than patching example files in place.
4. Live-fetch OpenRouter free models from `https://openrouter.ai/api/v1/models` and present them as optional suggestions.
5. Always allow manual provider, base URL, and model entry for any OpenAI-compatible setup.
6. Collect plugin configuration values during prompting, then install and configure plugins after Stavrobot is running.
7. Use Stavrobot's authenticated HTTP plugin-management endpoints instead of asking the LLM to install plugins.
8. Rebuild with `docker compose up -d --build --force-recreate` whenever repo HEAD or generated config changes.
9. Leave Cloudflare worker automation and Shelley integration for Phase 2.

## Repo structure

```text
install-stavrobot.sh
lib/
  common.sh
  prompts.sh
  repo.sh
  docker.sh
  stavrobot_api.sh
  summary.sh
py/
  openrouter_models.py
  load_current_config.py
  render_env.py
  render_toml.py
  catalog_normalize.py
data/
  core-schema.json
  plugin-catalog.json
state/
  .gitkeep
```

## Exact Phase 1 flow

1. Validate prerequisites.
2. Validate Stavrobot repo path.
3. Refuse to pull if the upstream repo has dirty tracked changes.
4. `git pull --ff-only` the upstream repo.
5. Load defaults from `env.example` and `config.example.toml` plus current values from `.env` and `data/main/config.toml`.
6. Prompt for required settings first.
7. Prompt for optional settings and integrations.
8. Prompt for plugin selection and collect plugin config values.
9. Render `.env` and `data/main/config.toml`.
10. Detect whether repo HEAD or config changed.
11. Run `docker compose up -d --build --force-recreate` if needed.
12. Wait for Stavrobot readiness using authenticated HTTP checks.
13. Install and configure selected plugins through Stavrobot's HTTP API.
14. Print final URLs and manual next steps.

## Provider UX

### Anthropic

Prompt for:
- provider = `anthropic`
- model
- auth mode: `apiKey` or `authFile`

### OpenAI-compatible

Prompt for:
- provider label
- base URL
- model ID
- API key

Before prompting, try to fetch current OpenRouter free models and show them as suggestions alongside the OpenRouter v1 endpoint URL.

## Prompt semantics

- Blank input keeps current value if present, otherwise default.
- `SKIP` unsets an optional value.
- Secrets are masked by default.
- `--show-secrets` disables masking.

## Plugin handling

The installer should maintain a curated catalog of first-party Stavrobot plugins. For each selected plugin:

1. Prompt for required config values.
2. Prompt for optional config values.
3. Save selections in `state/last-plugin-inputs.json` with mode `0600`.
4. After startup, call Stavrobot to install the plugin.
5. Then call Stavrobot to configure the plugin.
6. Verify the plugin appears in the installed plugin list.

## Error policy

Hard fail on:
- invalid repo path
- dirty upstream repo before pull
- pull failure
- config render failure
- Docker Compose failure
- readiness failure
- selected plugin install/config failure

Soft warn on:
- OpenRouter fetch failure
- plugin already installed
- optional plugin skipped
- manual integrations not automated in Phase 1

## Phase 2

- Cloudflare email worker automation
- Shelley "Stavrobot mode"
- Optional Stavrobot history/events API work to support Shelley as a better frontend
- Shelley rebuild automation

## Discovered upstream limitation

While implementing Phase 1, we verified that current upstream Stavrobot exposes `provider`, `model`, `apiKey`, and `authFile` in `config.toml`, but no explicit base-URL field for arbitrary OpenAI-compatible endpoints. The installer can still present OpenRouter free-model suggestions and collect generic provider details, but full arbitrary OpenAI-compatible endpoint setup may require upstream Stavrobot changes in Phase 2.

## Implemented increment

The installer now supports Phase 1 core config generation plus a first pass at plugin prompting and plugin installation/configuration through Stavrobot's authenticated HTTP endpoints.

## Hardening updates

The installer now supports `--plugins-only`, reusing saved plugin state from `state/last-plugin-inputs.json`. Prompt handling for optional owner fields was also tightened so skipped values are omitted from generated config output.
