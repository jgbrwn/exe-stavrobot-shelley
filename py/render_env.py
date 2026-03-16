#!/usr/bin/env python3
import json
import sys

ORDER = ["TZ", "POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB", "COMPOSE_PROFILES"]


def main() -> int:
    payload = json.load(sys.stdin)
    for key in ORDER:
        value = payload.get(key)
        if value is None or value == "":
            continue
        print(f"{key}={value}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
