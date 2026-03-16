#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit('usage: catalog_normalize.py CATALOG_PATH')
    catalog = json.loads(Path(sys.argv[1]).read_text())
    if not isinstance(catalog, list):
        raise SystemExit('catalog must be a list')
    print(json.dumps(catalog, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
