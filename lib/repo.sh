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
