#!/usr/bin/env python3
import asyncio
import json
import os
import urllib.error
import urllib.request
from email import policy
from email.parser import BytesParser

SEND_URL = os.environ.get("EXEDEV_SEND_URL", "http://169.254.169.254/gateway/email/send")
OWNER_EMAIL = os.environ.get("OWNER_EMAIL", "").strip().lower()


def log(msg: str) -> None:
    print(f"[exedev-smtp-relay] {msg}", flush=True)


def extract_text_body(raw: bytes) -> tuple[str, str]:
    parsed = BytesParser(policy=policy.default).parsebytes(raw)
    subject = (parsed.get("subject") or "(no subject)").strip()

    if parsed.is_multipart():
      for part in parsed.walk():
        if part.get_content_type() == "text/plain" and part.get_content_disposition() != "attachment":
          try:
            text = part.get_content()
            return subject, text if isinstance(text, str) else str(text)
          except Exception:
            continue
      return subject, "(no text/plain body; message may contain HTML or attachments)"

    try:
      content = parsed.get_content()
      if isinstance(content, str):
        return subject, content
      return subject, str(content)
    except Exception:
      return subject, raw.decode("utf-8", errors="replace")


def send_via_exedev(subject: str, body: str) -> tuple[bool, str]:
    payload = json.dumps({"to": OWNER_EMAIL, "subject": subject, "body": body}).encode("utf-8")
    req = urllib.request.Request(
        SEND_URL,
        data=payload,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="replace") or "{}")
            if data.get("success") is True:
                return True, "ok"
            return False, str(data.get("error") or "unknown send error")
    except urllib.error.HTTPError as e:
        try:
            body = e.read().decode("utf-8", errors="replace")
        except Exception:
            body = ""
        return False, f"http {e.code}: {body}"
    except Exception as e:  # noqa: BLE001
        return False, str(e)


def parse_path_value(arg: str) -> str:
    val = arg.strip()
    if ":" in val:
        _, val = val.split(":", 1)
    val = val.strip()
    if val.startswith("<") and val.endswith(">"):
        val = val[1:-1].strip()
    return val


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    peer = writer.get_extra_info("peername")
    log(f"connection from {peer}")
    writer.write(b"220 exedev-smtp-relay ESMTP\r\n")
    await writer.drain()

    mail_from = ""
    rcpt_to = ""

    while True:
        line = await reader.readline()
        if not line:
            break
        command = line.decode("utf-8", errors="replace").rstrip("\r\n")
        upper = command.upper()

        if upper.startswith("EHLO"):
            writer.write(b"250-exedev-smtp-relay\r\n250-AUTH PLAIN LOGIN\r\n250 SIZE 1048576\r\n")
        elif upper.startswith("HELO"):
            writer.write(b"250 exedev-smtp-relay\r\n")
        elif upper.startswith("MAIL FROM:"):
            mail_from = parse_path_value(command[len("MAIL FROM:"):])
            writer.write(b"250 2.1.0 OK\r\n")
        elif upper.startswith("RCPT TO:"):
            candidate = parse_path_value(command[len("RCPT TO:"):]).lower()
            if not OWNER_EMAIL:
                writer.write(b"554 5.0.0 Relay not configured\r\n")
            elif candidate != OWNER_EMAIL:
                writer.write(b"550 5.7.1 exe.dev relay only allows sending to OWNER_EMAIL\r\n")
            else:
                rcpt_to = candidate
                writer.write(b"250 2.1.5 OK\r\n")
        elif upper == "RSET":
            mail_from = ""
            rcpt_to = ""
            writer.write(b"250 2.0.0 Reset\r\n")
        elif upper == "NOOP":
            writer.write(b"250 2.0.0 OK\r\n")
        elif upper.startswith("AUTH PLAIN"):
            writer.write(b"235 2.7.0 Authentication successful\r\n")
        elif upper == "AUTH LOGIN":
            writer.write(b"334 VXNlcm5hbWU6\r\n")
            await writer.drain()
            _user = await reader.readline()
            writer.write(b"334 UGFzc3dvcmQ6\r\n")
            await writer.drain()
            _pass = await reader.readline()
            writer.write(b"235 2.7.0 Authentication successful\r\n")
        elif upper.startswith("AUTH"):
            writer.write(b"235 2.7.0 Authentication successful\r\n")
        elif upper == "DATA":
            if not mail_from or not rcpt_to:
                writer.write(b"503 5.5.1 Need MAIL FROM and RCPT TO first\r\n")
            else:
                writer.write(b"354 End data with <CR><LF>.<CR><LF>\r\n")
                await writer.drain()
                data_lines = []
                while True:
                    dline = await reader.readline()
                    if not dline:
                        break
                    if dline in (b".\r\n", b".\n"):
                        break
                    if dline.startswith(b".."):
                        dline = dline[1:]
                    data_lines.append(dline)
                raw = b"".join(data_lines)
                subject, body = extract_text_body(raw)
                ok, reason = send_via_exedev(subject, body)
                if ok:
                    log(f"forwarded email from={mail_from} to={rcpt_to} subject={subject!r}")
                    writer.write(b"250 2.0.0 Message accepted\r\n")
                else:
                    log(f"send failure: {reason}")
                    writer.write(f"554 5.0.0 Send failed: {reason}\r\n".encode("utf-8", errors="replace"))
        elif upper == "QUIT":
            writer.write(b"221 2.0.0 Bye\r\n")
            await writer.drain()
            break
        else:
            writer.write(b"500 5.5.2 Command unrecognized\r\n")

        await writer.drain()

    writer.close()
    await writer.wait_closed()


async def main() -> None:
    listen_host = os.environ.get("LISTEN_HOST", "0.0.0.0")
    listen_port = int(os.environ.get("LISTEN_PORT", "2525"))
    if not OWNER_EMAIL:
        raise SystemExit("OWNER_EMAIL is required")
    server = await asyncio.start_server(handle_client, listen_host, listen_port)
    addrs = ", ".join(str(sock.getsockname()) for sock in (server.sockets or []))
    log(f"listening on {addrs}; owner={OWNER_EMAIL}")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
