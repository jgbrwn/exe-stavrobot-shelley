#!/usr/bin/env python3
import json
import re
import sys
import tomllib
from pathlib import Path


def load_toml(path: Path) -> dict:
    return tomllib.loads(path.read_text())


def cmd_get_current(path: Path) -> int:
    data = load_toml(path)
    provider = data.get("provider", "")
    model = data.get("model", "")
    auth_mode = ""
    if data.get("apiKey"):
        auth_mode = "apiKey"
    elif data.get("authFile"):
        auth_mode = "authFile"

    available = provider == "openrouter" and auth_mode in {"apiKey", "authFile"}
    payload = {
        "status": "ok",
        "provider": provider,
        "model": model,
        "openrouter_model_selection_available": available,
        "auth_mode": auth_mode,
    }
    if not available:
        if provider != "openrouter":
            payload["reason"] = "provider_is_not_openrouter"
        elif not auth_mode:
            payload["reason"] = "auth_not_configured"
    print(json.dumps(payload, indent=2))
    return 0


def cmd_set_model(path: Path, model: str) -> int:
    text = path.read_text()
    pattern = re.compile(r'(?m)^model\s*=\s*"[^"]*"\s*$')
    replacement = f'model = {json.dumps(model)}'
    new_text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise SystemExit("expected exactly one top-level model assignment in config.toml")
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(new_text)
    tmp_path.replace(path)
    print(json.dumps({"status": "ok", "model": model}, indent=2))
    return 0


def main() -> int:
    if len(sys.argv) < 3:
        raise SystemExit("usage: stavrobot_model_control.py <get-current|set-model> CONFIG_PATH [MODEL]")
    command = sys.argv[1]
    path = Path(sys.argv[2])
    if command == "get-current":
        return cmd_get_current(path)
    if command == "set-model":
        if len(sys.argv) != 4:
            raise SystemExit("usage: stavrobot_model_control.py set-model CONFIG_PATH MODEL")
        return cmd_set_model(path, sys.argv[3])
    raise SystemExit(f"unknown command: {command}")


if __name__ == "__main__":
    raise SystemExit(main())
