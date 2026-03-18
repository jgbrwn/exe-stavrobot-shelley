#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

assert_contains_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'expected %s to contain: %s\n' "$file" "$needle" >&2
    exit 1
  fi
}

assert_runtime_patch_contract() {
  local file="$1"

  assert_contains_file "$file" 'const supportedStavrobotRawMediaMaxBytes = 262144'
  assert_contains_file "$file" 'func validateStavrobotRawInlineArtifact(artifact StavrobotArtifact) (map[string]any, string) {'
  assert_contains_file "$file" 'unsupported raw media mime'
  assert_contains_file "$file" 'invalid raw media base64'
  assert_contains_file "$file" 'raw media payload exceeds max bytes'
  assert_contains_file "$file" 'raw media byte_length mismatch'

  assert_contains_file "$file" 'hasAssistantText := false'
  assert_contains_file "$file" 'if !hasAssistantText {'
  assert_contains_file "$file" 'MediaType: fmt.Sprint(rawRef["mime_type"])'
  assert_contains_file "$file" 'Data:      fmt.Sprint(rawRef["data_base64"])'

  assert_contains_file "$file" 'result.DisplayData["media_refs"] = mediaRefs'
}

assert_runtime_patch_contract "$ROOT_DIR/patches/shelley/series/0004-stavrobot-runtime-unit.patch"
assert_runtime_patch_contract "$ROOT_DIR/patches/shelley/s1-stavrobot-mode-cleaned-runtime-prototype.patch"

printf 'shelley runtime raw-media patch contract tests passed\n'
