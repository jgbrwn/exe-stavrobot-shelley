#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

SUPPORTED_SCHEMA_VERSION = 1
SUPPORTED_BRIDGE_CONTRACT_VERSION = 1
DEFAULT_PROFILE_PATH = Path(__file__).resolve().parent.parent / "state" / "shelley-bridge-profiles.json"


class ProfileError(Exception):
    pass


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError as exc:
        raise ProfileError(f"profile_state_file_missing: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ProfileError(f"profile_state_file_invalid_json: {path}: {exc}") from exc


def is_valid_base_url(value: str) -> bool:
    parsed = urlparse(value)
    return parsed.scheme in {"http", "https"} and bool(parsed.netloc)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ProfileError(message)


def validate_profile_name(name: str) -> None:
    require(bool(name), "requested_profile_missing")


def validate_document(data: dict) -> None:
    require(isinstance(data, dict), "profile_state_root_not_object")
    require(data.get("schema_version") == SUPPORTED_SCHEMA_VERSION, f"unsupported_schema_version: {data.get('schema_version')}")
    require(
        data.get("bridge_contract_version") == SUPPORTED_BRIDGE_CONTRACT_VERSION,
        f"unsupported_bridge_contract_version: {data.get('bridge_contract_version')}",
    )
    require(isinstance(data.get("profiles"), dict), "profiles_not_object")
    default_profile = data.get("default_profile")
    require(isinstance(default_profile, str) and default_profile, "default_profile_missing_or_invalid")


def resolve_profile(data: dict, name: str) -> dict:
    validate_profile_name(name)
    profiles = data["profiles"]
    require(name in profiles, f"requested_profile_missing: {name}")
    profile = profiles[name]
    require(isinstance(profile, dict), f"profile_not_object: {name}")
    require(profile.get("enabled") is True, f"requested_profile_disabled: {name}")

    bridge_path = profile.get("bridge_path")
    config_path = profile.get("config_path")
    base_url = profile.get("base_url")
    args = profile.get("args", [])

    require(isinstance(bridge_path, str) and bridge_path.startswith("/"), f"bridge_path_not_absolute: {name}")
    require(os.path.exists(bridge_path), f"bridge_path_missing: {bridge_path}")
    require(os.access(bridge_path, os.X_OK), f"bridge_path_not_executable: {bridge_path}")

    require(isinstance(config_path, str) and config_path.startswith("/"), f"config_path_not_absolute: {name}")
    require(os.path.exists(config_path), f"config_path_missing: {config_path}")
    require(os.access(config_path, os.R_OK), f"config_path_not_readable: {config_path}")

    require(isinstance(base_url, str) and is_valid_base_url(base_url), f"invalid_base_url: {base_url}")
    require(isinstance(args, list) and all(isinstance(item, str) for item in args), f"args_not_string_list: {name}")

    return {
        "name": name,
        "bridge_path": bridge_path,
        "base_url": base_url,
        "config_path": config_path,
        "args": args,
        "notes": profile.get("notes", ""),
    }


def load_and_resolve(path: Path, name: str | None) -> dict:
    data = load_json(path)
    validate_document(data)
    requested = name or data["default_profile"]
    return {
        "status": "ok",
        "profile_state_path": str(path),
        "schema_version": data["schema_version"],
        "bridge_contract_version": data["bridge_contract_version"],
        "default_profile": data["default_profile"],
        "resolved": resolve_profile(data, requested),
    }


def usage() -> None:
    raise SystemExit(
        "usage: shelley_bridge_profiles.py <print-default-path|validate|resolve> [PROFILE_STATE_PATH] [PROFILE_NAME]"
    )


def main() -> int:
    if len(sys.argv) < 2:
        usage()

    command = sys.argv[1]
    if command == "print-default-path":
        print(DEFAULT_PROFILE_PATH)
        return 0

    path = Path(sys.argv[2]) if len(sys.argv) >= 3 and sys.argv[2] else DEFAULT_PROFILE_PATH

    try:
        if command == "validate":
            data = load_json(path)
            validate_document(data)
            print(json.dumps({
                "status": "ok",
                "profile_state_path": str(path),
                "schema_version": data["schema_version"],
                "bridge_contract_version": data["bridge_contract_version"],
                "default_profile": data["default_profile"],
                "profile_names": sorted(data["profiles"].keys()),
            }, indent=2))
            return 0

        if command == "resolve":
            name = sys.argv[3] if len(sys.argv) >= 4 else None
            print(json.dumps(load_and_resolve(path, name), indent=2))
            return 0
    except ProfileError as exc:
        print(json.dumps({"status": "error", "error": str(exc)}))
        return 1

    usage()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
