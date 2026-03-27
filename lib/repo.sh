#!/usr/bin/env bash
set -euo pipefail

validate_stavrobot_repo() {
  local dir="$1"
  [[ -d "$dir" ]] || die "Stavrobot directory does not exist: $dir"
  [[ -d "$dir/.git" ]] || die "Not a git repository: $dir"
  [[ -f "$dir/env.example" ]] || die "Missing env.example in $dir"
  [[ -f "$dir/config.example.toml" ]] || die "Missing config.example.toml in $dir"
  [[ -f "$dir/docker-compose.yml" ]] || die "Missing docker-compose.yml in $dir"
}

check_repo_clean_for_pull() {
  local dir="$1"
  local output
  output=$(git -C "$dir" status --porcelain)
  if [[ -n "$output" ]]; then
    printf '%s\n' "$output" >&2
    die "Upstream stavrobot repo has local changes. Refusing to git pull."
  fi
}

get_repo_head() {
  local dir="$1"
  git -C "$dir" rev-parse HEAD
}

pull_latest_stavrobot() {
  local dir="$1"
  info "Pulling latest stavrobot in $dir"
  git -C "$dir" pull --ff-only
}

ensure_stavrobot_checkout() {
  local dir="$1"
  local repo_url="$2"

  if [[ -d "$dir/.git" ]]; then
    validate_stavrobot_repo "$dir"
    return 0
  fi

  if [[ -d "$dir" ]]; then
    if [[ -n "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]]; then
      die "Stavrobot directory exists but is not a git checkout: $dir"
    fi
  else
    local parent
    parent=$(dirname "$dir")
    if [[ ! -d "$parent" ]]; then
      mkdir -p "$parent" 2>/dev/null || die "Cannot create parent directory for --stavrobot-dir: $parent (use a user-owned path like \$HOME/stavrobot, or create/chown the target path first)"
    fi
  fi

  info "Cloning stavrobot into $dir"
  git clone "$repo_url" "$dir" || die "Failed to clone stavrobot into $dir (check path permissions and network access)"
  validate_stavrobot_repo "$dir"
}
