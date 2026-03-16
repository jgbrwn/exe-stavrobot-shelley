# Stavrobot installer

Phase 1 installer project for deploying and updating [stavrobot](https://github.com/skorokithakis/stavrobot) on an exe.dev VM.

## Phase 1 scope

- Pull latest upstream stavrobot first
- Interactively generate `.env` and `data/main/config.toml`
- Support Anthropic directly today
- Surface OpenRouter free-model suggestions and gather generic OpenAI-compatible details for future/upstream-compatible setups
- Live-fetch current OpenRouter free models as suggestions
- Start/rebuild Stavrobot with Docker Compose
- Collect plugin config values up front, then install/configure plugins against the running app
- Print clear post-install next steps for manual integrations

## Not in Phase 1

- Cloudflare email worker automation
- Shelley custom rebuilds
- Shelley "Stavrobot mode"
- Stavrobot code changes

## Intended layout

```text
/opt/stavrobot/                 # upstream clone
/opt/stavrobot-installer/       # this repo
```

## Planned usage

```bash
./install-stavrobot.sh --stavrobot-dir /opt/stavrobot
./install-stavrobot.sh --stavrobot-dir /opt/stavrobot --refresh
./install-stavrobot.sh --stavrobot-dir /opt/stavrobot --plugins-only
```

## Status

Planning and scaffold phase.

## Current implementation status

Implemented so far:

- Upstream Stavrobot repo validation and `git pull --ff-only`
- OpenRouter free-model fetch and local caching
- Interactive core config prompts
- Clean generation of `.env` and `data/main/config.toml`
- Docker Compose rebuild/recreate on change
- Basic authenticated readiness check against Stavrobot

Implemented next:

- Interactive plugin selection
- Required and optional plugin config prompts
- Saved plugin selections in `state/last-plugin-inputs.json`
- Install and configure selected plugins against the running Stavrobot instance after startup

## Plugin state

Selected plugin installs are saved to:

- `state/last-plugin-inputs.json`

This file may contain plugin secrets. It is written with mode `0600`.

## Current caveats

- `--plugins-only` reuses `state/last-plugin-inputs.json` if present.
- Generic OpenAI-compatible provider prompting is present, but current upstream Stavrobot config still lacks an explicit arbitrary base-URL field.
- Email worker automation is still not implemented.
- Non-interactive automation is not finished yet.

## Manual integrations still left to the operator

The installer can generate config for these, but Phase 1 still leaves final activation manual:

- `authFile` login flow
- Signal registration/linking
- WhatsApp QR linking
- Cloudflare Email Worker deployment
- Claude Code login for the coder container

## Plugin run report

The most recent plugin install/configure results are written to:

- `state/last-plugin-report.txt`
