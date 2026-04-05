# exe-stavrobot-shelley (public quickstart)

Install and run [Stavrobot](https://github.com/skorokithakis/stavrobot) on an [exe.dev](https://exe.dev) VM, with optional managed [Shelley](https://github.com/boldsoftware/shelley) integration.

## 5-minute VM quickstart

```bash
# 0) use user-owned paths (avoid /opt permission issues on fresh VMs)
export STAVROBOT_DIR="$HOME/stavrobot"
export MANAGED_SHELLEY_DIR="$HOME/managed_shelley"

# 1) clone installer
git clone https://github.com/jgbrwn/exe-stavrobot-shelley.git "$HOME/stavrobot-installer"
cd "$HOME/stavrobot-installer"

# 2) preflight (safe)
./install-stavrobot.sh --doctor

# 3) install Stavrobot (interactive provider/key setup)
./install-stavrobot.sh --stavrobot-dir "$STAVROBOT_DIR"

# 4) optional: managed Shelley refresh + release-lane memory suitability gate
./install-stavrobot.sh --refresh-shelley-mode-release
```

Notes:

- `MANAGED_SHELLEY_DIR` tells installer-managed Shelley status/refresh lanes where your Shelley checkout lives.
- Using `$HOME/managed_shelley` makes it explicit this is the installer-managed Shelley checkout.
- If `--stavrobot-dir` does not exist, installer now auto-clones Stavrobot there.


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

## Email inbound options: Cloudflare worker or exe.dev receive-email bridge

You can use **either** path for inbound email into Stavrobot `/email/webhook`:

### Option A: Cloudflare email worker (default Stavrobot path)

```bash
# 1) Generate worker bundle from current Stavrobot config
./install-stavrobot.sh --configure-cloudflare-email-worker --stavrobot-dir "$STAVROBOT_DIR"

# 2) Optional: deploy worker + upload WEBHOOK_SECRET automatically
./install-stavrobot.sh --configure-cloudflare-email-worker --deploy-cloudflare-email-worker --stavrobot-dir "$STAVROBOT_DIR"
```

Manual Cloudflare portal step still required:

1. Open **Cloudflare Dashboard → Email → Email Routing** for your domain.
2. Create/confirm route(s) to worker `stavrobot-email-worker` (or your override name).
3. Send a test email and verify Stavrobot receives `/email/webhook` traffic.

### Option B: exe.dev receive-email bridge (no Cloudflare required)

```bash
# Install/enable Maildir -> /email/webhook bridge service
./install-stavrobot.sh --configure-exedev-email-bridge --stavrobot-dir "$STAVROBOT_DIR"

# Later, disable/stop the bridge service
./install-stavrobot.sh --configure-exedev-email-bridge --disable-exedev-email-bridge --stavrobot-dir "$STAVROBOT_DIR"
```

Plus one manual exe.dev CLI step (run from your local machine):

```bash
ssh exe.dev share receive-email <vm-name> on
```

Then send test mail to `anything@<vm-name>.exe.xyz` and verify Stavrobot logs.

You can switch between Option A and Option B at any time by enabling one path and disabling the other integration.

### Outbound mode options (in installer)

During `./install-stavrobot.sh --stavrobot-dir ...` email setup, choose one:

- `SMTP outbound + webhook inbound` (general outbound recipients)
- `exe.dev relay outbound (owner-email only) + webhook inbound`
- `Inbound-only (disable outbound send_email)`

If you choose exe.dev relay outbound, installer configures Stavrobot SMTP to a local relay shim that calls exe.dev send-email API. This is constrained to your exe.dev account email by platform rules.

Non-interactive override flags are also supported:

```bash
./install-stavrobot.sh --stavrobot-dir "$STAVROBOT_DIR" --config-only \
  --email-mode exedev-relay \
  --email-webhook-secret '<secret>' \
  --email-owner 'you@example.com'
```

## Private Modal endpoint option (Qwen3.5-9B)

You can configure a private Modal-hosted endpoint (OpenAI-compatible) via a local proxy that injects Modal auth headers.

Configure it:

```bash
./install-stavrobot.sh --configure-private-modal-qwen --stavrobot-dir "$STAVROBOT_DIR" \
  --private-modal-upstream-url 'https://<workspace>--<app>.modal.run' \
  --private-modal-token-id 'ak-...' \
  --private-modal-token-secret 'as-...' \
  --private-modal-set-default
```

What this does:

- writes a `docker-compose.private-modal-llm.override.yml` service (`private-modal-llm-proxy`)
- routes Stavrobot to `http://host.docker.internal:11435/v1`
- stores a reusable provider profile in `state/llm-profiles.json`

Disable later:

```bash
./install-stavrobot.sh --configure-private-modal-qwen --disable-private-modal-qwen --stavrobot-dir "$STAVROBOT_DIR"
```

You can keep both OpenRouter and private Modal profiles configured, then switch with:

```bash
./manage-stavrobot-model.sh list-profiles --stavrobot-dir "$STAVROBOT_DIR"
./manage-stavrobot-model.sh apply-profile --stavrobot-dir "$STAVROBOT_DIR" --profile private-modal-qwen
```

## Most-used commands

```bash
# refresh upstream stavrobot
./install-stavrobot.sh --stavrobot-dir "$HOME/stavrobot" --refresh

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
- If installer says it cannot create/clone into your `--stavrobot-dir`, switch to a user-owned path (for example `$HOME/stavrobot`) or create/chown your target path first.
- If Docker permission errors appear, add your user to `docker` group and re-login.
- If Shelley refresh fails, run:
  - `./install-stavrobot.sh --print-shelley-mode-status --basic`
  - `./install-stavrobot.sh --refresh-shelley-mode-release`
- If Cloudflare email is not receiving:
  - ensure VM is public (`share set-public`) and using the intended shared port
  - ensure Cloudflare Email Routing rule is created to the deployed worker
  - verify worker secret `WEBHOOK_SECRET` matches Stavrobot config
- If exe.dev bridge email is not receiving:
  - ensure `ssh exe.dev share receive-email <vm-name> on` is enabled
  - check bridge service logs: `sudo journalctl -u stavrobot-exedev-email-bridge -f`
  - verify Maildir has messages under `~/Maildir/new/`

## Notes

- Provider/API key setup is handled by the interactive installer flow.
- OpenRouter path includes live model suggestions.
- Advanced architecture/patch docs live under `docs/`.

## Known limitations

- Cloudflare Email Routing rule creation is still manual in the Cloudflare portal.
- exe.dev relay outbound mode is owner-email-only (exe.dev restriction): Stavrobot `send_email` to non-owner recipients will fail.
- Some integrations (Signal/WhatsApp/authFile/login flows) still include manual operator activation steps.
- Non-interactive full automation is not complete yet; the guided interactive installer path is the primary supported user flow.

## Optional screenshots for docs maintainers

When you are ready, add these under `docs/public/` and reference them here:

- installer doctor success output
- first-run installer completion summary
- Cloudflare Email Routing dashboard route example
- exe.dev email bridge service status/log screenshot
- managed Shelley status (`--print-shelley-mode-status --basic`)

## Permissions and path guidance (exe.dev)

Use user-owned paths by default:

- installer repo: `$HOME/stavrobot-installer`
- Stavrobot checkout: `$HOME/stavrobot`
- managed Shelley checkout: `$HOME/managed_shelley`

Why: cloning/building under `/opt/...` can fail for non-root users on fresh VMs.

If you *want* `/opt/...`, create/chown once first:

```bash
sudo mkdir -p /opt/stavrobot-installer /opt/stavrobot /opt/shelley
sudo chown -R "$USER:$USER" /opt/stavrobot-installer /opt/stavrobot /opt/shelley
```

Managed Shelley refresh/status uses `MANAGED_SHELLEY_DIR` when set; otherwise it defaults to `/opt/shelley`.

So with home-dir paths, export once before using Shelley commands:

```bash
export MANAGED_SHELLEY_DIR="$HOME/managed_shelley"
```

If you keep `/opt/shelley`, ensure it exists and is user-writable (create/chown as above).
