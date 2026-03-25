# Memory-suitability required-runtime checkpoints

## 2026-03-24 — local strict-lane checkpoint

Status: **local execution on dev VM**.

Rendered with:

```bash
./ci/render-memory-suitability-checkpoint-note.sh \
  --artifact-dir state/ci-artifacts-memory-suitability-20260324T181354Z \
  --run-ref local:2026-03-24T18:13:54Z-required-runtime-gate \
  --output state/ci-artifacts-memory-suitability-20260324T181354Z/checkpoint-note.md
```

Checkpoint note:

### Local strict memory-suitability checkpoint

- run: local:2026-03-24T18:13:54Z-required-runtime-gate
- artifact_dir: state/ci-artifacts-memory-suitability-20260324T181354Z
- diagnostics_timestamp_utc: 2026-03-24T18:13:54Z
- s4_last_report: present

Artifact files:
- s4-server.log <= /tmp/shelley-s4-recall-validation.log
- s4-runtime-contract.json <= /tmp/s4-runtime-contract.json
- s4-last-report.json <= /home/exedev/exe-stavrobot-shelley/state/s4-recall-validation-last.json
- diagnostics.txt <= generated

Notes:
- Local required-runtime lane policy: S4 softfail policy is strict.
- If this checkpoint failed, inspect s4-server.log and diagnostics.txt first.
