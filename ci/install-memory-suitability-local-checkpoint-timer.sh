#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
REPO_DIR="$ROOT_DIR"
SYSTEMD_DIR="/etc/systemd/system"
RUN_USER="exedev"
RUN_GROUP="exedev"
ON_CALENDAR="*-*-* 06:17:00 UTC"
ENABLE_NOW=1
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: ./ci/install-memory-suitability-local-checkpoint-timer.sh [flags]

Install/update local systemd service+timer for periodic memory-suitability checkpoints.

Flags:
  --repo-dir PATH        Repo directory for WorkingDirectory/ExecStart
  --systemd-dir PATH     Systemd unit directory (default: /etc/systemd/system)
  --run-user USER        Service user (default: exedev)
  --run-group GROUP      Service group (default: exedev)
  --on-calendar SPEC     Timer OnCalendar spec (default: *-*-* 06:17:00 UTC)
  --no-enable            Install units only; skip daemon-reload/enable/start
  --dry-run              Print planned actions without writing
  --help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-dir)
      REPO_DIR="$2"
      shift 2
      ;;
    --systemd-dir)
      SYSTEMD_DIR="$2"
      shift 2
      ;;
    --run-user)
      RUN_USER="$2"
      shift 2
      ;;
    --run-group)
      RUN_GROUP="$2"
      shift 2
      ;;
    --on-calendar)
      ON_CALENDAR="$2"
      shift 2
      ;;
    --no-enable)
      ENABLE_NOW=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "[error] Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -d "$REPO_DIR" ]] || { echo "[error] --repo-dir not found: $REPO_DIR" >&2; exit 1; }
[[ -x "$REPO_DIR/ci/run-memory-suitability-local-checkpoint.sh" ]] || {
  echo "[error] missing runner: $REPO_DIR/ci/run-memory-suitability-local-checkpoint.sh" >&2
  exit 1
}

service_path="$SYSTEMD_DIR/memory-suitability-local-checkpoint.service"
timer_path="$SYSTEMD_DIR/memory-suitability-local-checkpoint.timer"

service_body="[Unit]
Description=Local memory-suitability required-runtime checkpoint
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$RUN_USER
Group=$RUN_GROUP
WorkingDirectory=$REPO_DIR
ExecStart=$REPO_DIR/ci/run-memory-suitability-local-checkpoint.sh --policy strict
"

timer_body="[Unit]
Description=Schedule local memory-suitability required-runtime checkpoint

[Timer]
OnCalendar=$ON_CALENDAR
Persistent=true
Unit=memory-suitability-local-checkpoint.service

[Install]
WantedBy=timers.target
"

if (( DRY_RUN == 1 )); then
  echo "[dry-run] write $service_path"
  echo "[dry-run] write $timer_path"
  if (( ENABLE_NOW == 1 )); then
    echo "[dry-run] sudo systemctl daemon-reload"
    echo "[dry-run] sudo systemctl enable --now memory-suitability-local-checkpoint.timer"
  fi
  exit 0
fi

mkdir -p "$SYSTEMD_DIR"
printf '%s\n' "$service_body" > "$service_path"
printf '%s\n' "$timer_body" > "$timer_path"

echo "[info] wrote $service_path"
echo "[info] wrote $timer_path"

if (( ENABLE_NOW == 1 )); then
  sudo systemctl daemon-reload
  sudo systemctl enable --now memory-suitability-local-checkpoint.timer
  echo "[info] enabled timer: memory-suitability-local-checkpoint.timer"
  echo "[info] status: systemctl status memory-suitability-local-checkpoint.timer --no-pager"
fi
