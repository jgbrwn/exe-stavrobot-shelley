#!/usr/bin/env bash
set -euo pipefail

prompt_text() {
  local label="$1"
  local current="${2-}"
  local response
  if [[ -n "$current" ]]; then
    read -r -p "$label [$current]: " response
  else
    read -r -p "$label: " response
  fi
  printf '%s\n' "$response"
}

prompt_yes_no() {
  local label="$1"
  local default="${2:-N}"
  local prompt="$label [$default]: "
  local response
  read -r -p "$prompt" response
  response=${response:-$default}
  case "$response" in
    y|Y|yes|YES) return 0 ;;
    n|N|no|NO) return 1 ;;
    *) warn "Please answer yes or no"; prompt_yes_no "$label" "$default" ;;
  esac
}
