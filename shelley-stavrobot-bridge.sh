#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$ROOT_DIR/lib/common.sh"

STAVROBOT_DIR=""
CONFIG_PATH=""
BASE_URL="${STAVROBOT_BASE_URL:-http://localhost:8000}"
PASSWORD=""
MESSAGE=""
SOURCE="shelley"
SENDER="shelley"
STATE_FILE="$ROOT_DIR/state/last-stavrobot-client-session.json"
STATEFUL=1
COMMAND="chat"
EXTRACT=""
PRETTY=0
CONNECT_TIMEOUT=10
REQUEST_TIMEOUT=300
RETRIES=1
RETRY_DELAY=2
CONVERSATION_ID=""
STAVROBOT_SESSION_BIN="${STAVROBOT_SESSION_BIN:-$ROOT_DIR/shelley-stavrobot-session.sh}"
STAVROBOT_CLIENT_BIN="${STAVROBOT_CLIENT_BIN:-$ROOT_DIR/client-stavrobot.sh}"
STAVROBOT_BRIDGE_FIXTURE="${STAVROBOT_BRIDGE_FIXTURE:-}"
STAVROBOT_BRIDGE_RAW_MEDIA_ENABLED="${STAVROBOT_BRIDGE_RAW_MEDIA_ENABLED:-1}"
STAVROBOT_BRIDGE_RAW_MEDIA_MAX_BYTES="${STAVROBOT_BRIDGE_RAW_MEDIA_MAX_BYTES:-262144}"

usage() {
  cat <<'EOF'
Usage: ./shelley-stavrobot-bridge.sh [flags]

Default behavior:
  - canonical Shelley-facing bridge
  - defaults to stateful chat with saved conversation reuse
  - defaults to printing full JSON bridge output for Shelley/runtime callers

Commands:
  chat            Send a chat turn (default)
  show-session    Show saved local session state
  reset-session   Remove saved local session state
  messages        Fetch messages for current/specified conversation
  events          Fetch events for current/specified conversation

Flags:
  --stateful              Use saved conversation state (default)
  --stateless             Do not use saved conversation state
  --stavrobot-dir PATH    Read password from PATH/data/main/config.toml
  --config-path PATH      Read password from config.toml
  --base-url URL          Stavrobot base URL
  --password VALUE        Override password directly
  --message TEXT          Message to send; if omitted, read stdin for chat
  --conversation-id ID    Explicit conversation ID override
  --source NAME           Source field (default: shelley)
  --sender NAME           Sender field (default: shelley)
  --state-file PATH       Override local session state path
  --extract FIELD         response|conversation_id|message_id|ok|base_url|source|sender

Notes:
  - default output is full JSON so Shelley/runtime callers can parse response text plus IDs
  - chat output now also includes narrow S2-ready fields like content/display/raw while preserving response/conversation_id/message_id
  - use --extract response for human-oriented text-only output
  - bridge now also attempts to enrich compact tool_summary from the events endpoint when chat payload lacks direct event/display fields
  - bridge now also attempts narrow image/media reference extraction into artifacts.image from payload, response text URLs, and recent event summaries
  - when STAVROBOT_BRIDGE_FIXTURE=tool_summary is set, chat output injects deterministic display.tool_summary only if no real summary is available (test/validation aid)
  - when STAVROBOT_BRIDGE_FIXTURE=raw_media_image is set, chat output injects a deterministic inline raw image artifact only if no real image artifact is present (test/validation aid)
  - when STAVROBOT_BRIDGE_FIXTURE=runtime_raw_media_only is set, chat output forces content[] empty and injects a valid raw-inline image artifact (runtime native-mapping gate validation aid)
  - when STAVROBOT_BRIDGE_FIXTURE=runtime_invalid_raw_media is set, chat output forces content[] empty and injects an intentionally invalid raw-inline image artifact (runtime rejection-path validation aid)
  - when STAVROBOT_BRIDGE_FIXTURE=s2_markdown_tool_summary is set, chat output rewrites content[] to markdown-first with deterministic heading and ensures compact display.tool_summary (S2 runtime adaptation validation aid)
  --pretty                Pretty-print JSON output
  --connect-timeout SEC   Curl connect timeout in seconds
  --request-timeout SEC   Total request timeout in seconds
  --retries COUNT         Retry count on transport failure
  --retry-delay SEC       Sleep between retries
  --help

Environment:
  STAVROBOT_SESSION_BIN   Override session helper used by the bridge
  STAVROBOT_CLIENT_BIN    Override client helper used by the bridge
  STAVROBOT_BRIDGE_FIXTURE  Optional test fixture payload mode (e.g. tool_summary, raw_media_image, runtime_raw_media_only, runtime_invalid_raw_media, s2_markdown_tool_summary)
  STAVROBOT_BRIDGE_RAW_MEDIA_ENABLED  Enable/disable narrow raw-media extraction (1/0, default: 1)
  STAVROBOT_BRIDGE_RAW_MEDIA_MAX_BYTES  Max decoded bytes per raw media item (default: 262144)
EOF
}

run_session() {
  local -a cmd
  cmd=(
    "$STAVROBOT_SESSION_BIN"
    --base-url "$BASE_URL"
    --state-file "$STATE_FILE"
    --connect-timeout "$CONNECT_TIMEOUT"
    --request-timeout "$REQUEST_TIMEOUT"
    --retries "$RETRIES"
    --retry-delay "$RETRY_DELAY"
  )
  if [[ -n "$STAVROBOT_DIR" ]]; then
    cmd+=(--stavrobot-dir "$STAVROBOT_DIR")
  fi
  if [[ -n "$CONFIG_PATH" ]]; then
    cmd+=(--config-path "$CONFIG_PATH")
  fi
  if [[ -n "$PASSWORD" ]]; then
    cmd+=(--password "$PASSWORD")
  fi
  if [[ -n "$CONVERSATION_ID" ]]; then
    cmd+=(--conversation-id "$CONVERSATION_ID")
  fi
  if [[ -n "$SOURCE" ]]; then
    cmd+=(--source "$SOURCE")
  fi
  if [[ -n "$SENDER" ]]; then
    cmd+=(--sender "$SENDER")
  fi
  if (( PRETTY )); then
    cmd+=(--pretty)
  fi
  if [[ -n "$EXTRACT" ]]; then
    cmd+=(--extract "$EXTRACT")
  fi
  "${cmd[@]}" "$@"
}

run_client() {
  local -a cmd
  cmd=(
    "$STAVROBOT_CLIENT_BIN"
    --base-url "$BASE_URL"
    --connect-timeout "$CONNECT_TIMEOUT"
    --request-timeout "$REQUEST_TIMEOUT"
    --retries "$RETRIES"
    --retry-delay "$RETRY_DELAY"
  )
  if [[ -n "$STAVROBOT_DIR" ]]; then
    cmd+=(--stavrobot-dir "$STAVROBOT_DIR")
  fi
  if [[ -n "$CONFIG_PATH" ]]; then
    cmd+=(--config-path "$CONFIG_PATH")
  fi
  if [[ -n "$PASSWORD" ]]; then
    cmd+=(--password "$PASSWORD")
  fi
  if [[ -n "$EXTRACT" ]]; then
    cmd+=(--extract "$EXTRACT")
  fi
  if (( PRETTY )); then
    cmd+=(--pretty)
  fi
  "${cmd[@]}" "$@"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    chat|show-session|reset-session|messages|events)
      COMMAND="$1"
      shift
      ;;
    --stateful)
      STATEFUL=1
      shift
      ;;
    --stateless)
      STATEFUL=0
      shift
      ;;
    --stavrobot-dir)
      STAVROBOT_DIR="$2"
      shift 2
      ;;
    --config-path)
      CONFIG_PATH="$2"
      shift 2
      ;;
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    --message)
      MESSAGE="$2"
      shift 2
      ;;
    --conversation-id)
      CONVERSATION_ID="$2"
      shift 2
      ;;
    --source)
      SOURCE="$2"
      shift 2
      ;;
    --sender)
      SENDER="$2"
      shift 2
      ;;
    --state-file)
      STATE_FILE="$2"
      shift 2
      ;;
    --extract)
      EXTRACT="$2"
      shift 2
      ;;
    --pretty)
      PRETTY=1
      EXTRACT=""
      shift
      ;;
    --connect-timeout)
      CONNECT_TIMEOUT="$2"
      shift 2
      ;;
    --request-timeout)
      REQUEST_TIMEOUT="$2"
      shift 2
      ;;
    --retries)
      RETRIES="$2"
      shift 2
      ;;
    --retry-delay)
      RETRY_DELAY="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ "$CONNECT_TIMEOUT" =~ ^[0-9]+$ ]] || die "--connect-timeout must be an integer"
[[ "$REQUEST_TIMEOUT" =~ ^[0-9]+$ ]] || die "--request-timeout must be an integer"
[[ "$RETRIES" =~ ^[0-9]+$ ]] || die "--retries must be an integer"
[[ "$RETRY_DELAY" =~ ^[0-9]+$ ]] || die "--retry-delay must be an integer"
[[ "$STAVROBOT_BRIDGE_RAW_MEDIA_ENABLED" =~ ^[01]$ ]] || die "STAVROBOT_BRIDGE_RAW_MEDIA_ENABLED must be 0 or 1"
[[ "$STAVROBOT_BRIDGE_RAW_MEDIA_MAX_BYTES" =~ ^[0-9]+$ ]] || die "STAVROBOT_BRIDGE_RAW_MEDIA_MAX_BYTES must be an integer"
(( RETRIES >= 1 )) || die "--retries must be at least 1"
(( STAVROBOT_BRIDGE_RAW_MEDIA_MAX_BYTES > 0 )) || die "STAVROBOT_BRIDGE_RAW_MEDIA_MAX_BYTES must be greater than 0"

render_bridge_chat_json() {
  local response_json="$1"
  local events_json="${2:-}"
  python3 - "$response_json" "$STAVROBOT_BRIDGE_FIXTURE" "$events_json" "$STAVROBOT_BRIDGE_RAW_MEDIA_ENABLED" "$STAVROBOT_BRIDGE_RAW_MEDIA_MAX_BYTES" <<'PY'
import base64, binascii, hashlib, json, re, sys
from urllib.parse import urlparse

payload = json.loads(sys.argv[1])
fixture = sys.argv[2]
events_json = sys.argv[3]
raw_media_enabled = sys.argv[4] == '1'
raw_media_max_bytes = int(sys.argv[5])
response = payload.get('response', '')
out = {
    'ok': True,
    'response': response,
    'conversation_id': payload.get('conversation_id', ''),
    'message_id': payload.get('message_id', ''),
    'content': [],
    'display': {},
    'raw': payload,
}
if response:
    out['content'].append({'kind': 'markdown', 'text': response})

tool_summary = []
summary_seen = set()


def append_summary_item(item):
    if not isinstance(item, dict):
        return
    tool = str(item.get('tool') or item.get('name') or item.get('type') or 'tool')
    status = str(item.get('status') or item.get('result') or 'ok')
    title = str(item.get('title') or item.get('summary') or item.get('message') or '')
    if tool == 'tool' and not title:
        return
    key = (tool, status, title)
    if key in summary_seen:
        return
    summary_seen.add(key)
    tool_summary.append({'tool': tool, 'status': status, 'title': title})


# Prefer direct payload display summary when present.
display = payload.get('display')
if isinstance(display, dict):
    for item in (display.get('tool_summary') or []):
        append_summary_item(item)

# Then accept direct payload event-ish lists.
if not tool_summary:
    for key in ('events', 'tool_events', 'tool_summary'):
        value = payload.get(key)
        if isinstance(value, list) and value:
            for item in value:
                append_summary_item(item)
            if tool_summary:
                break

parsed_events = None
if events_json:
    try:
        parsed_events = json.loads(events_json)
    except Exception:
        parsed_events = None

# If chat payload was text-only, enrich from events endpoint output when available.
if not tool_summary and isinstance(parsed_events, dict):
    events = parsed_events.get('events') or []
    if isinstance(events, list):
        for item in events[-8:]:
            if not isinstance(item, dict):
                continue
            # Keep only tool-oriented event types for compact summary.
            event_type = str(item.get('type') or '')
            if event_type and not event_type.startswith('tool_'):
                continue
            append_summary_item(item)

if fixture == 'tool_summary' and not tool_summary:
    tool_summary = [{
        'tool': 'fixture.tool_summary',
        'status': 'ok',
        'title': 'fixture generated tool summary for managed smoke validation',
    }]
if tool_summary:
    out['display']['tool_summary'] = tool_summary[:8]

artifact_seen = set()
raw_media_seen = set()
artifacts = []
media_notes = []
url_pattern = re.compile(r'https?://[^\s)\]>",]+')
image_exts = ('.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.bmp')
allowed_raw_image_mimes = {
    'image/png',
    'image/jpeg',
    'image/jpg',
    'image/gif',
    'image/webp',
}

def looks_like_image_url(url):
    try:
        path = urlparse(url).path.lower()
    except Exception:
        return False
    return any(path.endswith(ext) for ext in image_exts)

def add_image_artifact(url, title=''):
    if not isinstance(url, str) or not url:
        return
    if not url.startswith('http://') and not url.startswith('https://'):
        return
    if not looks_like_image_url(url):
        return
    if ('url', url) in artifact_seen:
        return
    artifact_seen.add(('url', url))
    artifacts.append({'kind': 'image', 'url': url, 'title': str(title or '')})


def extract_urls_from_text(text):
    if not isinstance(text, str) or not text:
        return []
    return url_pattern.findall(text)


def normalize_mime(value):
    if not isinstance(value, str):
        return ''
    mime = value.strip().lower()
    if not mime:
        return ''
    if ';' in mime:
        mime = mime.split(';', 1)[0].strip()
    if mime == 'image/jpg':
        mime = 'image/jpeg'
    return mime


def decode_base64_media(raw_value):
    if not isinstance(raw_value, str):
        return None, 'missing-data'
    raw = raw_value.strip()
    if not raw:
        return None, 'missing-data'
    if raw.startswith('data:') and ',' in raw:
        raw = raw.split(',', 1)[1]
    try:
        decoded = base64.b64decode(raw, validate=True)
    except (binascii.Error, ValueError):
        return None, 'invalid-base64'
    if not decoded:
        return None, 'empty-data'
    return decoded, ''


def add_raw_media_artifact(item, source_key=''):
    if not raw_media_enabled:
        return
    if not isinstance(item, dict):
        return
    mime = normalize_mime(item.get('mime_type') or item.get('mime') or item.get('content_type') or item.get('type') or '')
    if mime and mime not in allowed_raw_image_mimes:
        media_notes.append(f'ignored raw media with unsupported mime {mime}')
        return
    raw_value = (
        item.get('data_base64')
        or item.get('base64')
        or item.get('b64')
        or item.get('data')
        or item.get('content')
    )
    decoded, err = decode_base64_media(raw_value)
    if err:
        media_notes.append(f'ignored raw media ({source_key or "payload"}): {err}')
        return
    byte_len = len(decoded)
    if byte_len > raw_media_max_bytes:
        media_notes.append(f'ignored raw media ({source_key or "payload"}): too-large ({byte_len} > {raw_media_max_bytes})')
        return
    digest = hashlib.sha256(decoded).hexdigest()
    if digest in raw_media_seen:
        return
    raw_media_seen.add(digest)
    title = str(item.get('title') or item.get('name') or item.get('label') or item.get('alt') or '')
    effective_mime = mime or 'image/png'
    artifacts.append({
        'kind': 'image',
        'mime_type': effective_mime,
        'transport': 'raw_inline_base64',
        'byte_length': byte_len,
        'data_base64': base64.b64encode(decoded).decode('ascii'),
        'title': title,
    })


def maybe_add_raw_media_from_item(item, source_key=''):
    if not isinstance(item, dict):
        return
    # Preserve current narrow URL path first.
    url = item.get('url') or item.get('href') or item.get('src') or item.get('image_url') or item.get('download_url')
    kind = str(item.get('kind') or item.get('type') or item.get('mime') or '').lower()
    title = item.get('title') or item.get('name') or item.get('label') or item.get('alt') or ''
    if 'image' in kind or looks_like_image_url(str(url or '')):
        add_image_artifact(str(url or ''), title)
    add_raw_media_artifact(item, source_key)


# 1) First try direct payload media/artifact-like fields.
for key in ('artifacts', 'images', 'media', 'attachments', 'files'):
    value = payload.get(key)
    if not isinstance(value, list):
        continue
    for item in value:
        if isinstance(item, str):
            add_image_artifact(item)
            continue
        maybe_add_raw_media_from_item(item, key)

# 1b) Try top-level raw media fields for bounded first-cut support.
for top_key in ('image_base64', 'screenshot_base64', 'media_base64'):
    top_value = payload.get(top_key)
    if isinstance(top_value, str) and top_value.strip():
        add_raw_media_artifact({'data_base64': top_value, 'mime_type': payload.get('mime_type') or payload.get('content_type')}, top_key)

# 2) Try common top-level image URL fields.
for key in ('image_url', 'screenshot_url', 'thumbnail_url'):
    add_image_artifact(str(payload.get(key) or ''))

# 3) Fall back to URLs found in response text.
if not artifacts:
    for url in extract_urls_from_text(response):
        add_image_artifact(url)

# 4) Last resort: URLs found in recent event summaries.
if not artifacts and isinstance(parsed_events, dict):
    events = parsed_events.get('events') or []
    if isinstance(events, list):
        for item in events[-8:]:
            if not isinstance(item, dict):
                continue
            title = item.get('title') or item.get('name') or ''
            for field in ('summary', 'message', 'title'):
                for url in extract_urls_from_text(str(item.get(field) or '')):
                    add_image_artifact(url, title)

if fixture == 'raw_media_image':
    has_image_artifact = any(isinstance(item, dict) and item.get('kind') == 'image' for item in artifacts)
    if not has_image_artifact:
        raw_fixture = base64.b64encode(b'fixture-raw-image').decode('ascii')
        artifacts.append({
            'kind': 'image',
            'mime_type': 'image/png',
            'transport': 'raw_inline_base64',
            'byte_length': len(b'fixture-raw-image'),
            'data_base64': raw_fixture,
            'title': 'fixture raw media image for managed smoke validation',
        })

if fixture == 'runtime_raw_media_only':
    out['content'] = []
    has_raw_image = any(
        isinstance(item, dict)
        and item.get('kind') == 'image'
        and (item.get('transport') == 'raw_inline_base64' or item.get('data_base64'))
        for item in artifacts
    )
    if not has_raw_image:
        raw_fixture = base64.b64encode(b'runtime-raw-only-image').decode('ascii')
        artifacts.append({
            'kind': 'image',
            'mime_type': 'image/png',
            'transport': 'raw_inline_base64',
            'byte_length': len(b'runtime-raw-only-image'),
            'data_base64': raw_fixture,
            'title': 'fixture runtime raw-media only artifact',
        })

if fixture == 'runtime_invalid_raw_media':
    out['content'] = []
    artifacts.append({
        'kind': 'image',
        'mime_type': 'image/png',
        'transport': 'raw_inline_base64',
        'byte_length': 12,
        'data_base64': '%%%not-base64%%%',
        'title': 'fixture runtime invalid raw-media artifact',
    })

if fixture == 'runtime_unsupported_raw_mime':
    out['content'] = []
    raw_fixture = base64.b64encode(b'runtime-unsupported-mime').decode('ascii')
    artifacts.append({
        'kind': 'image',
        'mime_type': 'text/plain',
        'transport': 'raw_inline_base64',
        'byte_length': len(b'runtime-unsupported-mime'),
        'data_base64': raw_fixture,
        'title': 'fixture runtime unsupported raw-media mime',
    })

if fixture == 'runtime_oversize_raw_media':
    out['content'] = []
    oversize = b'x' * (262144 + 1)
    artifacts.append({
        'kind': 'image',
        'mime_type': 'image/png',
        'transport': 'raw_inline_base64',
        'byte_length': len(oversize),
        'data_base64': base64.b64encode(oversize).decode('ascii'),
        'title': 'fixture runtime oversize raw-media artifact',
    })

if fixture == 's2_markdown_tool_summary':
    out['content'] = [
        {
            'kind': 'markdown',
            'text': '## S2 fixture heading\n\nS2 markdown + tool-summary fixture body.',
        }
    ]
    out['response'] = '## S2 fixture heading\n\nS2 markdown + tool-summary fixture body.'
    display = out.setdefault('display', {})
    tool_summary = display.get('tool_summary')
    if not isinstance(tool_summary, list) or not tool_summary:
        display['tool_summary'] = [
            {
                'tool': 'fixture.s2_tool',
                'status': 'ok',
                'title': 'fixture S2 markdown/tool-summary validation',
            }
        ]

if media_notes:
    out.setdefault('display', {})['media_notes'] = media_notes[:8]

if artifacts:
    out['artifacts'] = artifacts
if not out['display']:
    out.pop('display')
print(json.dumps(out, indent=2))
PY
}

fetch_chat_events_json() {
  local chat_json="$1"
  local conv_id
  conv_id=$(python3 - "$chat_json" <<'PY'
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    print("")
    raise SystemExit(0)
print(data.get('conversation_id') or "")
PY
)
  [[ -n "$conv_id" ]] || return 0

  local events_json
  if events_json=$(run_client events --conversation-id "$conv_id" 2>/dev/null); then
    printf '%s\n' "$events_json"
  fi
}

case "$COMMAND" in
  chat)
    if (( STATEFUL )); then
      if [[ -n "$MESSAGE" ]]; then
        chat_json=$(run_session chat --message "$MESSAGE")
      else
        chat_json=$(run_session chat)
      fi
    else
      args=(chat)
      if [[ -n "$MESSAGE" ]]; then
        args+=(--message "$MESSAGE")
      fi
      if [[ -n "$CONVERSATION_ID" ]]; then
        args+=(--conversation-id "$CONVERSATION_ID")
      fi
      if [[ -n "$SOURCE" ]]; then
        args+=(--source "$SOURCE")
      fi
      if [[ -n "$SENDER" ]]; then
        args+=(--sender "$SENDER")
      fi
      chat_json=$(run_client "${args[@]}")
    fi

    if [[ -n "$EXTRACT" ]]; then
      python3 - "$EXTRACT" "$chat_json" <<'PY'
import json, sys
field, response_json = sys.argv[1:3]
data = json.loads(response_json)
value = data.get(field, '')
if isinstance(value, bool):
    print('true' if value else 'false')
elif value is None:
    print('')
elif isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
    else
      events_json=""
      if [[ -z "$STAVROBOT_BRIDGE_FIXTURE" || "$STAVROBOT_BRIDGE_FIXTURE" == "tool_summary" || "$STAVROBOT_BRIDGE_FIXTURE" == "raw_media_image" ]]; then
        events_json=$(fetch_chat_events_json "$chat_json" || true)
      fi
      render_bridge_chat_json "$chat_json" "$events_json"
    fi
    ;;
  show-session)
    run_session show
    ;;
  reset-session)
    run_session reset
    ;;
  messages)
    if (( STATEFUL )); then
      run_session messages
    else
      [[ -n "$CONVERSATION_ID" ]] || die "--conversation-id is required with --stateless messages"
      run_client messages --conversation-id "$CONVERSATION_ID"
    fi
    ;;
  events)
    if (( STATEFUL )); then
      run_session events
    else
      [[ -n "$CONVERSATION_ID" ]] || die "--conversation-id is required with --stateless events"
      run_client events --conversation-id "$CONVERSATION_ID"
    fi
    ;;
esac
