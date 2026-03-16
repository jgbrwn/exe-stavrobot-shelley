#!/usr/bin/env python3
import json
import sys
import tomllib
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


def parse_toml(path: Path) -> dict:
    if not path.exists():
        return {}
    return tomllib.loads(path.read_text())


def main() -> int:
    if len(sys.argv) != 5:
        raise SystemExit('usage: load_current_config.py ENV_EXAMPLE ENV_CURRENT TOML_EXAMPLE TOML_CURRENT')
    payload = {
        'env_example': parse_env(Path(sys.argv[1])),
        'env_current': parse_env(Path(sys.argv[2])),
        'toml_example': parse_toml(Path(sys.argv[3])),
        'toml_current': parse_toml(Path(sys.argv[4])),
    }
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
