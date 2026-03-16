#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path


def parse_env(path: Path) -> dict:
    data = {}
    if not path.exists():
        return data
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        data[key] = value
    return data


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit('usage: load_current_config.py ENV_PATH CURRENT_ENV_PATH')
    example = parse_env(Path(sys.argv[1]))
    current = parse_env(Path(sys.argv[2]))
    print(json.dumps({"example": example, "current": current}, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
