# Shelley managed patch-series handoff (`0001`..`0009`)

## Scope

This record captures RC handoff status for the managed Shelley Stavrobot patch series owned in this repo under:

- `patches/shelley/series/0001-*.patch`
- ...
- `patches/shelley/series/0009-*.patch`

## Baseline upstream ref

- target ref: `5b072309d8a086b6a4fe8a550b473c5805d73ae5`
- short: `5b07230`

## Artifact validation (source-of-truth repo)

Validator command:

```bash
./validate-shelley-patch-series.sh \
  --upstream-checkout /tmp/shelley-official \
  --upstream-ref 5b07230
```

Result:

- `git apply --check` for `0001..0009`: pass
- sequential apply `0001..0009`: pass
- UI install/build: pass
- `go test ./server/... ./db/...`: pass

## `/opt/shelley` application result

Because `/opt/shelley` initially had local drift, a safety backup and clean apply lane were used.

Pre-apply backup:

- path: `/tmp/opt-shelley-preapply-backup-20260326T233637`
- contents:
  - `status.txt`
  - `tracked.diff`
  - `untracked.txt`
  - `untracked/*` copy

Apply flow:

1. `git -C /opt/shelley reset --hard 5b07230`
2. `git -C /opt/shelley clean -fd`
3. apply `0001..0009` in series order
4. run:
   - `npx --yes pnpm@10.28.0 -C ui install --frozen-lockfile`
   - `npx --yes pnpm@10.28.0 -C ui run build`
   - `go test ./server/... ./db/...`

Result: all pass.

## Risk notes (RC)

- low-to-medium: handler-side status/error mapping surfaces (`0005`/`0006`/`0009`)
- low: UI safety-gating behavior drift (`0007`)
- low: tests/contracts/docs (`0008`)
- known debt: not-found mapping currently follows existing wrapped-error text pattern (`"conversation not found"`); future typed error plumbing is preferred when touching hydration boundaries.

## Installer alignment status

- `validate-shelley-patch-series.sh` now validates full `0001..0009` stack.
- `refresh-shelley-managed-s1.sh` now applies full `0001..0009` stack and bumps patch metadata version for managed rebuild state.
- root `README.md` references were updated to reflect `0001..0009` scope.

## Consumer/publicization implication

For end-user/public release readiness, this patch-series lane is now internally coherent (`series docs` + `validator` + `refresh helper` all aligned to `0001..0009`).

Remaining release/publicization work is mainly packaging/docs hardening (onboarding, env prerequisites, bootstrap commands, operational guardrails), not patch-series correctness.
