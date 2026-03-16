#!/usr/bin/env bash
set -euo pipefail

info() {
  printf '[info] %s\n' "$*"
}

warn() {
  printf '[warn] %s\n' "$*" >&2
}

die() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

sha256_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf 'missing\n'
    return 0
  fi
  sha256sum "$path" | awk '{print $1}'
}

ensure_private_file() {
  local path="$1"
  touch "$path"
  chmod 600 "$path"
}

mask_secret() {
  local value="$1"
  local len=${#value}
  if (( len == 0 )); then
    printf '[unset]'
  elif (( len <= 4 )); then
    printf '****'
  else
    printf '%s****%s' "${value:0:2}" "${value: -2}"
  fi
}

json_get() {
  local file="$1"
  local path="$2"
  python3 - "$file" "$path" <<'PY'
import json, sys
from functools import reduce
file_path, path = sys.argv[1], sys.argv[2]
with open(file_path) as f:
    data = json.load(f)
cur = data
for part in path.split('.'):
    if part == '':
        continue
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print('')
        raise SystemExit(0)
if isinstance(cur, bool):
    print('true' if cur else 'false')
elif cur is None:
    print('')
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur))
else:
    print(cur)
PY
}
