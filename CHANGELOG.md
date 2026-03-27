# Changelog

All notable changes to this project will be documented in this file.

## v0.1.0-public

Initial public launch baseline.

Highlights:

- Public consumer quickstart (`README_PUBLIC.md`)
- Installer preflight doctor (`--doctor`, `--doctor --json`)
- Managed Shelley release-lane alias (`--refresh-shelley-mode-release`)
- Managed Shelley patch-series alignment through `0001..0009`
- Cloudflare email worker helper entrypoint in installer:
  - `--configure-cloudflare-email-worker`
  - `--deploy-cloudflare-email-worker`
- Explicit exe.dev proxy/public URL docs (`https://<vm-name>.exe.xyz`, no `:8000` for primary public URL)
- Public repo hygiene files:
  - `LICENSE`
  - `CONTRIBUTING.md`
  - `SECURITY.md`
  - issue/PR templates
