#!/usr/bin/env python3
import argparse
import email
import email.policy
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.request
from email.utils import parseaddr
from pathlib import Path


def log(message: str) -> None:
    print(f"[exedev-email-bridge] {message}", flush=True)


def parse_message(path: Path) -> tuple[str, str, str]:
    raw_bytes = path.read_bytes()
    raw_text = raw_bytes.decode("utf-8", errors="replace")
    parsed = email.message_from_bytes(raw_bytes, policy=email.policy.default)

    from_header = parsed.get("From", "")
    from_addr = parseaddr(from_header)[1].strip().lower()

    delivered_to_header = parsed.get("Delivered-To", "")
    delivered_to_addr = parseaddr(delivered_to_header)[1].strip().lower()
    to_header = parsed.get("To", "")
    to_addr = delivered_to_addr or parseaddr(to_header)[1].strip().lower()

    return from_addr, to_addr, raw_text


def post_webhook(webhook_url: str, webhook_secret: str, from_addr: str, to_addr: str, raw_text: str, timeout: float) -> None:
    body = json.dumps({"from": from_addr, "to": to_addr, "raw": raw_text}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {webhook_secret}",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        if resp.status < 200 or resp.status >= 300:
            raise RuntimeError(f"webhook returned {resp.status}")


def safe_move(src: Path, dest_dir: Path) -> None:
    dest_dir.mkdir(parents=True, exist_ok=True)
    candidate = dest_dir / src.name
    if candidate.exists():
        candidate = dest_dir / f"{src.name}.{int(time.time())}"
    shutil.move(str(src), str(candidate))


def process_once(maildir_root: Path, webhook_url: str, webhook_secret: str, timeout: float) -> int:
    new_dir = maildir_root / "new"
    cur_dir = maildir_root / "cur"
    failed_dir = maildir_root / "failed"

    new_dir.mkdir(parents=True, exist_ok=True)
    cur_dir.mkdir(parents=True, exist_ok=True)
    failed_dir.mkdir(parents=True, exist_ok=True)

    processed = 0
    for message_path in sorted(new_dir.iterdir(), key=lambda p: p.name):
        if not message_path.is_file():
            continue
        try:
            from_addr, to_addr, raw_text = parse_message(message_path)
            if not from_addr or not to_addr:
                raise RuntimeError("missing From or Delivered-To/To address")
            post_webhook(webhook_url, webhook_secret, from_addr, to_addr, raw_text, timeout)
            safe_move(message_path, cur_dir)
            processed += 1
            log(f"forwarded {message_path.name} from={from_addr} to={to_addr}")
        except urllib.error.HTTPError as e:
            log(f"webhook http error for {message_path.name}: {e.code}; will retry")
        except urllib.error.URLError as e:
            log(f"webhook network error for {message_path.name}: {e}; will retry")
        except Exception as e:  # noqa: BLE001
            log(f"failed parsing/forwarding {message_path.name}: {e}; moving to failed/")
            safe_move(message_path, failed_dir)
    return processed


def main() -> int:
    parser = argparse.ArgumentParser(description="Forward exe.dev Maildir messages to Stavrobot /email/webhook")
    parser.add_argument("--maildir-root", default=os.path.expanduser("~/Maildir"))
    parser.add_argument("--webhook-url", required=True)
    parser.add_argument("--webhook-secret", required=True)
    parser.add_argument("--poll-interval-seconds", type=float, default=2.0)
    parser.add_argument("--request-timeout-seconds", type=float, default=10.0)
    args = parser.parse_args()

    maildir_root = Path(args.maildir_root)
    webhook_url = args.webhook_url.rstrip("/")

    log(f"starting maildir_root={maildir_root} webhook_url={webhook_url}")
    while True:
        try:
            process_once(maildir_root, webhook_url, args.webhook_secret, args.request_timeout_seconds)
        except Exception as e:  # noqa: BLE001
            log(f"loop error: {e}")
        time.sleep(args.poll_interval_seconds)


if __name__ == "__main__":
    raise SystemExit(main())
