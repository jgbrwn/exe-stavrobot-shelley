# Shelley/Stavrobot next-steps handoff

## Snapshot (current)

- Repo branch: `main`
- Latest commits on this track:
  - `5993edd` Record strict managed runtime raw-media proof checkpoint
  - `d0af7e8` Document Shelley managed runtime proof and cleanup recipes
  - `cc93f52` Add runtime raw-media smoke assertions and checkout reset ergonomics
  - `b1d8d1c` Add bridge raw-media negative-case regression test
- Repo tests: `./tests/run.sh` passing
- Patch-series validator: previously passing (`./validate-shelley-patch-series.sh`)
- `/opt/shelley` status: currently clean (`main...origin/main`)

Local/untracked repo artifacts expected:

- `state/current-config.json`
- `state/last-plugin-report.txt`
- `state/openrouter-free-models.json`
- `state/render-config.json`
- `state/render-env.json`

## What just landed

1. Bridge negative-case regression pack is in place:
   - invalid mime
   - invalid base64
   - oversize raw media

2. Managed runtime smoke assertions now include behavior-level checks for:
   - phase-2 native raw-media gate
   - runtime rejection of invalid raw media

3. Deterministic fixture modes now cover runtime proof needs:
   - `runtime_raw_media_only`
   - `runtime_invalid_raw_media`
   - `runtime_unsupported_raw_mime`
   - `runtime_oversize_raw_media`

4. `/opt/shelley` cleanliness ergonomics improved:
   - `--print-clean-reset-instructions`
   - `--clean-reset-only --i-understand-reset`

5. Strict managed proof commands were run and documented in:
   - `docs/SHELLEY_DISPLAY_DATA_FIXTURE_VALIDATION_NOTE.md`

## Immediate next actions (recommended)

### A) Make strict raw-media proofs the default "authoritative" managed refresh profile

Today strict raw-media assertions are opt-in flags. Next improvement is a single convenience mode (or documented blessed command) that always includes:

- `--smoke-expect-native-raw-media-gating`
- `--smoke-require-native-raw-media-hints`
- `--smoke-expect-raw-media-rejection`
- `--smoke-require-raw-media-rejection-hints`

This reduces operator drift and makes proof quality consistent.

### B) Add a repo-owned one-command strict runtime proof driver

Create a dedicated helper (or test wrapper) that runs the four deterministic fixtures in sequence against managed `/opt/shelley` and emits a compact pass/fail report with DB paths.

Goal: make rerunning the exact proof bundle trivial during handoffs.

### C) Decide CI policy for managed-runtime smoke contract test

`tests/test-shelley-managed-smoke-raw-media-runtime-contract.sh` is intentionally skip-safe when managed runtime is not present/patched. Decide whether to:

- keep skip-safe behavior for generic dev environments, and
- add a CI lane (or release checklist step) that ensures a patched managed checkout exists before invoking this test.

## Outward roadmap (post-immediate)

### 1) Narrow S2 fidelity step (highest outward priority)

Build on current runtime seam to improve native Shelley fidelity with minimal risk:

- preserve compact display metadata as canonical (`display_data`)
- keep text fallback mandatory
- avoid broad content-model changes until clear upstream-compatible mapping is validated

Primary references:

- `docs/SHELLEY_RUNTIME_ADAPTATION_CONTRACT.md`
- `docs/SHELLEY_S2_STRUCTURED_BRIDGE_TARGET.md`

### 2) Patch artifact/source parity discipline

Continue ensuring changes in managed runtime behavior are reflected in both:

- `patches/shelley/series/0004-stavrobot-runtime-unit.patch`
- `patches/shelley/s1-stavrobot-mode-cleaned-runtime-prototype.patch`

and covered by targeted regression tests.

### 3) S4 recall evidence before retrieval-layer expansion

Before introducing Shelley-side retrieval orchestration, execute the recall validation template and gather evidence:

- `docs/SHELLEY_S4_RECALL_VALIDATION_TEMPLATE.md`

## Fast resume commands for next conversation

Check current status:

```bash
git status --short --branch
./print-shelley-managed-status.sh
./tests/run.sh
```

If managed runtime proof is needed, first reapply/rebuild patch set:

```bash
./refresh-shelley-managed-s1.sh \
  --shelley-dir /opt/shelley \
  --profile-state-path /home/exedev/exe-stavrobot-shelley/state/shelley-bridge-profiles.json
```

Then run strict proof variants (examples):

```bash
./install-stavrobot.sh \
  --refresh-shelley-mode \
  --expect-shelley-native-raw-media-gating \
  --require-shelley-native-raw-media-hints \
  --expect-shelley-media-refs \
  --require-shelley-media-refs \
  --shelley-bridge-fixture runtime_raw_media_only

./install-stavrobot.sh \
  --refresh-shelley-mode \
  --expect-shelley-raw-media-rejection \
  --require-shelley-raw-media-rejection-hints \
  --shelley-bridge-fixture runtime_invalid_raw_media
```

Clean managed checkout when done:

```bash
./refresh-shelley-managed-s1.sh --clean-reset-only --i-understand-reset
```
