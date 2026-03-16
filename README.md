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

- Shelley custom rebuilds
- Shelley "Stavrobot mode"
- Stavrobot code changes

## Phase 2 in progress

Two Phase 2 tracks have now started:

### Cloudflare automation

- `install-cloudflare-email-worker.sh` generates a deployable Cloudflare Email Worker bundle from existing Stavrobot config
- output includes `worker.js`, `wrangler.toml`, `.dev.vars.example`, worker-specific `README.md`, and deployment `CHECKLIST.md`
- optional `--deploy` support can run Wrangler deploy and upload `WEBHOOK_SECRET`

Still manual in this track:

- Cloudflare account auth/login if not already set up
- Cloudflare Email Routing rule creation in the dashboard

### Shelley integration MVP

- `chat-with-stavrobot.sh` is a thin adapter around Stavrobot's authenticated `POST /chat` endpoint
- `docs/SHELLEY_STAVROBOT_MVP.md` records the recommended MVP and likely next upstream API asks

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

Phase 1 is implemented and usable. Phase 2 has started with the Cloudflare automation track.

## Current implementation status

Implemented so far:

- Upstream Stavrobot repo validation and `git pull --ff-only`
- OpenRouter free-model fetch and local caching
- Interactive core config prompts
- Clean generation of `.env` and `data/main/config.toml`
- Docker Compose rebuild/recreate on change
- Basic authenticated readiness check against Stavrobot
- Interactive plugin selection
- Required and optional plugin config prompts
- Saved plugin selections in `state/last-plugin-inputs.json`
- Install and configure selected plugins against the running Stavrobot instance after startup
- Phase 2 starter: Cloudflare email worker bundle generation
- Phase 2 starter: Shelley-to-Stavrobot chat adapter script

## Plugin state

Selected plugin installs are saved to:

- `state/last-plugin-inputs.json`

This file may contain plugin secrets. It is written with mode `0600`.

## Current caveats

- `--plugins-only` reuses `state/last-plugin-inputs.json` if present.
- Generic OpenAI-compatible provider prompting is present, but current upstream Stavrobot config still lacks an explicit arbitrary base-URL field.
- Cloudflare email worker automation currently generates/deploys the worker bundle, but Email Routing rule creation is still manual.
- Non-interactive automation is not finished yet.

## Manual integrations still left to the operator

The installer can generate config for these, but some final activation steps are still manual:

- `authFile` login flow
- Signal registration/linking
- WhatsApp QR linking
- Cloudflare Email Routing rule creation
- Claude Code login for the coder container

## Plugin run report

The most recent plugin install/configure results are written to:

- `state/last-plugin-report.txt`

## Cloudflare email worker automation

Generate a worker bundle from existing Stavrobot config:

```bash
./install-cloudflare-email-worker.sh --stavrobot-dir /opt/stavrobot
```

Override values or deploy directly:

```bash
./install-cloudflare-email-worker.sh \
  --stavrobot-dir /opt/stavrobot \
  --worker-name stavrobot-email-worker \
  --account-id YOUR_CF_ACCOUNT_ID \
  --deploy
```

This reads `publicHostname` and `email.webhookSecret` from `data/main/config.toml` when available.

Generated bundle location by default:

- `state/cloudflare-email-worker/`

Contents:

- `worker.js`
- `wrangler.toml`
- `.dev.vars.example`
- `README.md`
- `CHECKLIST.md`

## Shelley integration MVP

Send a message to a running Stavrobot instance through the adapter:

```bash
./chat-with-stavrobot.sh \
  --stavrobot-dir /opt/stavrobot \
  --message "Hello from Shelley"
```

Or pipe stdin:

```bash
printf 'Summarize the last deployment status' | ./chat-with-stavrobot.sh --stavrobot-dir /opt/stavrobot
```

By default the script prints only Stavrobot's `response` field. Use `--raw-json` to inspect the full API response.

Useful adapter flags:

- `--connect-timeout`
- `--request-timeout`
- `--retries`
- `--retry-delay`

Design notes live in:

- `docs/SHELLEY_STAVROBOT_MVP.md`

Additional API notes for Shelley follow-up:

- `docs/STAVROBOT_API_NOTES.md`
