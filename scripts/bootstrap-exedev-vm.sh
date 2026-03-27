#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/jgbrwn/exe-stavrobot-shelley.git}"
DEST_DIR="${DEST_DIR:-/opt/stavrobot-installer}"

if [[ $# -gt 0 ]]; then
  echo "Usage: $0"
  echo "Environment overrides: REPO_URL=... DEST_DIR=..."
  exit 1
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

install_if_missing() {
  local cmd="$1"
  local pkg="$2"
  if need_cmd "$cmd"; then
    echo "[ok] $cmd"
    return 0
  fi
  echo "[info] installing $pkg (missing command: $cmd)"
  sudo apt-get update -y >/dev/null
  sudo apt-get install -y "$pkg"
}

install_if_missing git git
install_if_missing curl curl
install_if_missing jq jq
install_if_missing python3 python3
install_if_missing tmux tmux
install_if_missing node nodejs
install_if_missing npm npm
install_if_missing docker docker.io

if ! groups | grep -q '\bdocker\b'; then
  echo "[info] adding $USER to docker group"
  sudo usermod -aG docker "$USER"
  echo "[warn] log out/in may be required before docker non-sudo commands work"
fi

if [[ ! -d "$DEST_DIR/.git" ]]; then
  echo "[info] cloning installer repo to $DEST_DIR"
  sudo mkdir -p "$(dirname "$DEST_DIR")"
  sudo chown -R "$USER":"$USER" "$(dirname "$DEST_DIR")"
  git clone "$REPO_URL" "$DEST_DIR"
else
  echo "[info] repo already present at $DEST_DIR; pulling latest"
  git -C "$DEST_DIR" pull --ff-only
fi

cd "$DEST_DIR"
./install-stavrobot.sh --doctor || {
  echo "[error] installer doctor failed; inspect output above"
  exit 1
}

echo
cat <<MSG
Bootstrap complete.

Next steps:
  cd $DEST_DIR
  ./install-stavrobot.sh --stavrobot-dir /opt/stavrobot
  ./install-stavrobot.sh --refresh-shelley-mode-release

MSG
