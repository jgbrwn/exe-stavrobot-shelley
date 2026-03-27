# Contributing

Thanks for contributing.

## Development workflow

1. Make focused changes with clear commit messages.
2. Run relevant tests before opening a PR:
   - `./tests/run.sh` (or targeted scripts under `tests/`)
   - installer preflight: `./install-stavrobot.sh --doctor`
3. For managed Shelley patch-series changes, keep `patches/shelley/series/README.md`, `validate-shelley-patch-series.sh`, and refresh tooling aligned.

## Safety

- Do not commit secrets, API keys, or runtime private state from `state/`.
- Keep provider-key setup interactive/user-supplied.
- Prefer additive, reversible changes.
