# Release checklist

Use this before tagging or publishing release artifacts.

## 1) Preflight

- [ ] `./install-stavrobot.sh --doctor`
- [ ] `./install-stavrobot.sh --doctor --json` (optional automation capture)

## 2) Test validation

- [ ] `./tests/run.sh`
- [ ] If managed Shelley patch artifacts changed:
  - [ ] `./validate-shelley-patch-series.sh --upstream-checkout /tmp/shelley-official --upstream-ref <ref>`

## 3) Managed Shelley release lane (memory/recall suitability)

- [ ] `./install-stavrobot.sh --refresh-shelley-mode-release`
- [ ] Capture `./install-stavrobot.sh --print-shelley-mode-status --basic`

## 4) Docs and hygiene

- [ ] `README_PUBLIC.md` matches current user install path
- [ ] Root `README.md` references remain accurate
- [ ] `CHANGELOG.md` updated for this milestone/release tag
- [ ] No secrets or private state files staged

## 5) Optional `/opt/shelley` handoff lane

- [ ] Apply patch series `0001..0009` in order to target upstream checkout
- [ ] UI build + `go test ./server/... ./db/...` pass
- [ ] Record baseline ref + validation evidence in handoff notes
