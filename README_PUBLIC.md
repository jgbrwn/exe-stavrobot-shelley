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

## Most-used commands

```bash
# refresh upstream stavrobot
./install-stavrobot.sh --stavrobot-dir /opt/stavrobot --refresh

# managed Shelley status
./install-stavrobot.sh --print-shelley-mode-status --basic

# managed Shelley strict refresh
./install-stavrobot.sh --refresh-shelley-mode-basic
```

## Notes

- Provider/API key setup is handled by the interactive installer flow.
- OpenRouter path includes live model suggestions.
- Advanced architecture/patch docs live under `docs/`.
