#!/usr/bin/env python3
import json
import sys
import urllib.request

URL = "https://openrouter.ai/api/v1/models"
PREFERRED = [
    "openrouter/free",
    "qwen/qwen3-coder:free",
    "openai/gpt-oss-120b:free",
    "openai/gpt-oss-20b:free",
    "meta-llama/llama-3.3-70b-instruct:free",
]


def main() -> int:
    req = urllib.request.Request(URL, headers={"User-Agent": "stavrobot-installer"})
    with urllib.request.urlopen(req, timeout=30) as response:
        payload = json.load(response)

    models = []
    for item in payload.get("data", []):
        pricing = item.get("pricing", {})
        if pricing.get("prompt") == "0" and pricing.get("completion") == "0":
            models.append(
                {
                    "id": item.get("id", ""),
                    "name": item.get("name", ""),
                    "context_length": item.get("context_length"),
                }
            )

    preferred_index = {model_id: index for index, model_id in enumerate(PREFERRED)}
    models.sort(key=lambda item: (preferred_index.get(item["id"], 9999), item["name"], item["id"]))
    json.dump({"endpoint": "https://openrouter.ai/api/v1", "models": models}, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
