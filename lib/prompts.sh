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

prompt_secret() {
  local label="$1"
  local display_current="${2-}"
  local response
  if [[ -n "$display_current" ]]; then
    read -r -s -p "$label [$display_current]: " response
    printf '\n' >&2
  else
    read -r -s -p "$label: " response
    printf '\n' >&2
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

prompt_choice() {
  local label="$1"
  shift
  local options=("$@")
  local i=1
  printf '%s\n' "$label" >&2
  for option in "${options[@]}"; do
    printf '  %d) %s\n' "$i" "$option" >&2
    ((i+=1))
  done
  local response
  while true; do
    read -r -p "Choice: " response
    if [[ "$response" =~ ^[0-9]+$ ]] && (( response >= 1 && response <= ${#options[@]} )); then
      printf '%s\n' "${options[$((response-1))]}"
      return 0
    fi
    warn "Invalid choice"
  done
}

prompt_multiline() {
  local label="$1"
  printf '%s\n' "$label" >&2
  printf '%s\n' 'Finish with a single line containing END' >&2
  local lines=()
  local line
  while IFS= read -r line; do
    [[ "$line" == "END" ]] && break
    lines+=("$line")
  done
  printf '%s\n' "${lines[*]}" | sed 's/ /\n/g'
}

prompt_optional_text() {
  local label="$1"
  local current="${2-}"
  local response
  if [[ -n "$current" ]]; then
    read -r -p "$label [$current]: " response
  else
    read -r -p "$label: " response
  fi
  if [[ "$response" == "SKIP" ]]; then
    printf '__SKIP__\n'
    return 0
  fi
  printf '%s\n' "$response"
}
