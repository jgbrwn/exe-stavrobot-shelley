#!/usr/bin/env python3
import json
import sys


def q(value: str) -> str:
    return json.dumps(value)


def main() -> int:
    payload = json.load(sys.stdin)
    out = []
    for key in ["provider", "model", "password", "apiKey", "authFile", "publicHostname"]:
        value = payload.get(key)
        if value in (None, ""):
            continue
        out.append(f"{key} = {q(value)}")
    custom_prompt = payload.get("customPrompt")
    if custom_prompt:
        out.append('customPrompt = """')
        out.append(custom_prompt)
        out.append('"""')
    sys.stdout.write("\n".join(out) + ("\n" if out else ""))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
