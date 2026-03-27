# exe-stavrobot-shelley (public quickstart)

Install and run Stavrobot on an exe.dev VM, with optional managed Shelley integration.

## 5-minute VM quickstart

```bash
# 1) clone
git clone https://github.com/<org>/exe-stavrobot-shelley.git /opt/stavrobot-installer
cd /opt/stavrobot-installer

# 2) preflight (safe)
./install-stavrobot.sh --doctor

# 3) install Stavrobot (interactive provider/key setup)
./install-stavrobot.sh --stavrobot-dir /opt/stavrobot

# 4) optional: managed Shelley refresh + release-lane memory suitability gate
./install-stavrobot.sh --refresh-shelley-mode-release
```

## Make your exe.dev VM public (for Telegram/webhook integrations)

By default, exe.dev HTTP proxy access is private.

To make your VM public, run from your local machine:

```bash
ssh exe.dev share set-public <vm-name>
```

To switch back to private access later:

```bash
ssh exe.dev share set-private <vm-name>
```

To ensure the proxy points at your Stavrobot port (default 8000):

```bash
ssh exe.dev share port <vm-name> 8000
```

Then your public base URL is:

- `https://<vm-name>.exe.xyz`

No `:8000` suffix is needed for the main shared/public port.

(For alternate internal ports in 3000-9999 you can still use `:port`, but those are not your primary public URL.)

## Cloudflare email worker (basic user flow)

```bash
# 1) Generate worker bundle from current Stavrobot config
./install-stavrobot.sh --configure-cloudflare-email-worker --stavrobot-dir /opt/stavrobot

# 2) Optional: deploy worker + upload WEBHOOK_SECRET automatically
./install-stavrobot.sh --configure-cloudflare-email-worker --deploy-cloudflare-email-worker --stavrobot-dir /opt/stavrobot
```

Manual Cloudflare portal step still required:

1. Open **Cloudflare Dashboard → Email → Email Routing** for your domain.
2. Create/confirm route(s) to worker `stavrobot-email-worker` (or your override name).
3. Send a test email and verify Stavrobot receives `/email/webhook` traffic.

## Most-used commands

```bash
# refresh upstream stavrobot
./install-stavrobot.sh --stavrobot-dir /opt/stavrobot --refresh

# managed Shelley status
./install-stavrobot.sh --print-shelley-mode-status --basic

# managed Shelley strict refresh
./install-stavrobot.sh --refresh-shelley-mode-basic
```

## Quick verification

```bash
# local health
curl -fsS http://localhost:8000/ >/dev/null && echo "local web ok"

# public health (after set-public)
curl -fsS https://<vm-name>.exe.xyz/ >/dev/null && echo "public web ok"
```

## Troubleshooting

- If `--doctor` fails, install missing tools first and rerun it.
- If Docker permission errors appear, add your user to `docker` group and re-login.
- If Shelley refresh fails, run:
  - `./install-stavrobot.sh --print-shelley-mode-status --basic`
  - `./install-stavrobot.sh --refresh-shelley-mode-release`
- If Cloudflare email is not receiving:
  - ensure VM is public (`share set-public`) and using the intended shared port
  - ensure Cloudflare Email Routing rule is created to the deployed worker
  - verify worker secret `WEBHOOK_SECRET` matches Stavrobot config

## Notes

- Provider/API key setup is handled by the interactive installer flow.
- OpenRouter path includes live model suggestions.
- Advanced architecture/patch docs live under `docs/`.
