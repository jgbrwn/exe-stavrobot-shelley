#!/usr/bin/env python3
import json
import sys


def q(value: str) -> str:
    return json.dumps(value)


def nonempty_items(section: dict) -> list[tuple[str, object]]:
    return [(key, value) for key, value in section.items() if value not in (None, "")]


def write_section(out: list[str], name: str, section: dict) -> None:
    items = nonempty_items(section)
    if not items:
        return
    out.append("")
    out.append(f"[{name}]")
    for key, value in items:
        out.append(f"{key} = {q(str(value))}")


def main() -> int:
    payload = json.load(sys.stdin)
    out: list[str] = []
    for key in ["provider", "model", "password", "apiKey", "authFile", "publicHostname"]:
        value = payload.get(key)
        if value in (None, ""):
            continue
        out.append(f"{key} = {q(str(value))}")
    custom_prompt = payload.get("customPrompt")
    if custom_prompt:
        out.append('customPrompt = """')
        out.append(custom_prompt)
        out.append('"""')

    write_section(out, "owner", payload.get("owner", {}))
    write_section(out, "coder", payload.get("coder", {}))
    write_section(out, "signal", payload.get("signal", {}))
    write_section(out, "telegram", payload.get("telegram", {}))
    if payload.get("whatsapp_enabled"):
        out.append("")
        out.append("[whatsapp]")
    email = payload.get("email", {})
    email_items = nonempty_items(email)
    if email_items:
        out.append("")
        out.append("[email]")
        for key, value in email_items:
            if key == "smtpPort":
                out.append(f"{key} = {int(value)}")
            else:
                out.append(f"{key} = {q(str(value))}")
    sys.stdout.write("\n".join(out).strip() + "\n")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
