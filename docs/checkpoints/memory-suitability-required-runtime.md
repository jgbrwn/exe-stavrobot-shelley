# Memory-suitability required-runtime checkpoints

## 2026-03-24 — local strict-lane rehearsal (pre-live CI dispatch)

Status: **local rehearsal only** (not a GitHub Actions run).

Reason: this VM currently has no GitHub CLI auth/session configured, so workflow dispatch/download could not be executed from here yet.

Rendered with:

```bash
./ci/render-memory-suitability-checkpoint-note.sh \
  --artifact-dir state/ci-artifacts-memory-suitability-20260324T181354Z \
  --run-url https://github.com/<org>/<repo>/actions/runs/<run_id> \
  --output state/ci-artifacts-memory-suitability-20260324T181354Z/checkpoint-note.md
```

Checkpoint note:

### CI strict memory-suitability checkpoint

- run: https://github.com/<org>/<repo>/actions/runs/<run_id>
- artifact_dir: state/ci-artifacts-memory-suitability-20260324T181354Z
- diagnostics_timestamp_utc: 2026-03-24T18:13:54Z
- s4_last_report: present

Artifact files:
- s4-server.log <= /tmp/shelley-s4-recall-validation.log
- s4-runtime-contract.json <= /tmp/s4-runtime-contract.json
- s4-last-report.json <= /home/exedev/exe-stavrobot-shelley/state/s4-recall-validation-last.json
- diagnostics.txt <= generated

Notes:
- CI lane policy: S4 softfail policy is strict.
- If this checkpoint failed, inspect s4-server.log and diagnostics.txt first.

---

### TODO for operational closure

1. Dispatch `.github/workflows/memory-suitability-required-runtime.yml` on a `shelley-required-runtime` runner.
2. Download uploaded `memory-suitability-required-runtime-artifacts` bundle from that run.
3. Re-render checkpoint note with the **real** run URL and artifact dir.
4. Append the live-run checkpoint below this rehearsal entry.
