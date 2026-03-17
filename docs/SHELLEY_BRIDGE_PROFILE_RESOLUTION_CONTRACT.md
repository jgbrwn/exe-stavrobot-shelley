# Shelley bridge profile resolution contract

## Purpose

Define the smallest concrete installer-managed bridge profile resolution contract that the cleaned Shelley S1 patch can depend on.

This contract is specifically about replacing the disposable hardcoded assumptions from the `/tmp/shelley-official` spike, namely:

- hardcoded bridge script path
- hardcoded `local-default` special case
- hardcoded Stavrobot config path
- hardcoded local base URL

## Design goal

The cleaned Shelley patch should only need to know:

- a profile name stored in `conversation_options.stavrobot.bridge_profile`
- where to read installer-managed local bridge profile state
- how to resolve that profile into executable bridge invocation details

It should **not** need to know:

- how the installer created the profile file
- how the profile values were originally chosen
- raw secrets
- arbitrary machine-global installer logic

## Source of truth

Recommended installer-managed source of truth file:

- `state/shelley-bridge-profiles.json`

If/when deployed onto the target VM outside this repo checkout, the installer may place that file somewhere machine-local and stable, but the contract should still be the same.

## Required file shape

Recommended minimum shape:

```json
{
  "schema_version": 1,
  "bridge_contract_version": 1,
  "default_profile": "local-default",
  "profiles": {
    "local-default": {
      "enabled": true,
      "bridge_path": "/opt/stavrobot-installer/shelley-stavrobot-bridge.sh",
      "base_url": "http://localhost:8000",
      "config_path": "/opt/stavrobot/data/main/config.toml",
      "args": ["--stateless"],
      "notes": "Local default Stavrobot instance"
    }
  },
  "updated_at": "2025-01-01T00:00:00Z"
}
```

## Required top-level fields

### `schema_version`

Meaning:

- version of the installer-owned file format

Initial value:

- `1`

### `bridge_contract_version`

Meaning:

- version of the Shelley↔installer bridge-profile resolution contract

Initial value:

- `1`

### `default_profile`

Meaning:

- default profile name the installer considers primary/suggested

Initial value example:

- `local-default`

### `profiles`

Meaning:

- map of installer-managed profile names to machine-local execution definitions

## Required per-profile fields

Each profile object must contain:

### `enabled`

Meaning:

- whether the profile is available for Shelley use

### `bridge_path`

Meaning:

- absolute path to the canonical Shelley-facing bridge executable

Rules:

- must be absolute
- must point to `shelley-stavrobot-bridge.sh` or a stable installer-managed equivalent
- must exist and be executable at runtime

### `base_url`

Meaning:

- base URL of the target Stavrobot instance

Rules:

- absolute URL string
- no trailing requirements beyond what bridge already accepts
- may point to `http://localhost:8000` in the typical local case

### `config_path`

Meaning:

- machine-local path to the Stavrobot `config.toml` used by the bridge for auth/config discovery

Rules:

- absolute file path
- must exist and be readable by the Shelley runtime if bridge invocation depends on it

### `args`

Meaning:

- installer-managed default arguments Shelley should pass before dynamic turn-specific args

Typical S1 example:

- `[
  "--stateless"
]`

Rules:

- list of literal argv items
- no shell parsing required
- may be empty

### `notes`

Meaning:

- optional human/operator-readable description

Rules:

- not required by Shelley runtime logic

## Explicit non-goals for profile file

Do not store:

- API keys
- Basic Auth passwords
- remote Stavrobot conversation IDs
- full Shelley rebuild state
- arbitrary shell snippets

The profile file is for narrow local bridge resolution only.

## Minimal Shelley-side resolution behavior

Given a conversation with:

```json
{
  "type": "stavrobot",
  "stavrobot": {
    "enabled": true,
    "bridge_profile": "local-default"
  }
}
```

the cleaned Shelley patch should do the following.

### Step 1: validate mode metadata

Require at least:

- `type == "stavrobot"`
- `stavrobot.enabled == true`
- non-empty `stavrobot.bridge_profile`

### Step 2: load installer-managed bridge profile file

Shelley must know one stable path from which to read the profile file.

Current recommendation:

- installer supplies that location via a small stable runtime setting or machine-local default path

The important point is that the cleaned patch reads installer-managed profile state instead of hardcoding it in source.

### Step 3: verify file-level compatibility

Require:

- `schema_version` supported
- `bridge_contract_version` supported

If unsupported:

- fail clearly with operator-actionable error

### Step 4: resolve named profile

Lookup:

- `profiles[bridge_profile]`

Require:

- profile exists
- `enabled == true`
- `bridge_path` exists and is executable
- `config_path` exists if required by current bridge usage

### Step 5: build argv for bridge invocation

Recommended S1 argv assembly:

1. start with `bridge_path`
2. append installer-managed `args`
3. append installer-managed `--config-path <config_path>`
4. append installer-managed `--base-url <base_url>`
5. append dynamic turn args such as:
   - `chat`
   - `--message <text>`
   - `--conversation-id <id>` if one already exists

Important:

- Shelley should treat each item as a literal argv token
- no shell string concatenation should be required

## Recommended runtime error cases

Shelley should classify bridge-profile resolution failures into operator-meaningful errors such as:

- profile state file missing
- unsupported `schema_version`
- unsupported `bridge_contract_version`
- requested profile missing
- requested profile disabled
- `bridge_path` missing or not executable
- `config_path` missing or unreadable
- invalid `base_url`

These should produce clear runtime errors rather than silently falling back to normal model behavior.

## Recommended resolution API inside Shelley

A cleaned Shelley patch will likely want an internal helper boundary conceptually like:

### Input

- `bridge_profile` name

### Output

A resolved structure conceptually containing:

- `bridge_path string`
- `base_url string`
- `config_path string`
- `args []string`

This is enough for the S1 bridge runner.

## Suggested file-location rule

The contract needs one stable way for Shelley to find the profile file.

Recommended initial options, in order of cleanliness:

### Option A: Shelley runtime config points to profile file

Best long-term shape.

Pros:

- explicit
- machine-portable
- easy to change without recompiling Shelley

### Option B: installer-managed default machine path

Acceptable S1 fallback if explicit config is not ready yet.

Example conceptual path:

- `/var/lib/stavrobot-installer/shelley-bridge-profiles.json`
- or another installer-owned stable path

Important:

- do **not** keep using a source-checkout-relative path in the cleaned patch

## Why this contract is enough for S1

S1 only needs enough information to:

- invoke the canonical bridge
- pass the right local config context
- continue an existing remote conversation when `conversation_id` exists
- persist updated remote IDs afterward

That means this contract can stay narrow.

It does not need to solve:

- global rebuild provenance
- model control admin state
- rich-output adaptation
- recall/retrieval behavior

## Relationship to installer-managed rebuild state

This bridge-profile resolution contract is narrower than the full rebuild contract.

In practice:

- rebuild state answers: *what Shelley was built/deployed, when, and with what patch/profile set*
- bridge profile file answers: *how a named conversation `bridge_profile` resolves locally right now*

That separation is intentional and should remain.

## Recommended validation behavior for cleaned patch

The cleaned Shelley patch should validate the profile resolution layer during:

- startup if practical
- or at first Stavrobot-mode turn if lazy loading is preferred

At minimum it should fail clearly when a selected profile cannot be resolved.

## Suggested next implementation step after this contract

Now that the bridge-profile resolution contract is concrete, the next useful step is to update the managed patch cleanup plan and patch assets so the cleaned Shelley patch explicitly targets this contract instead of the disposable hardcoded `local-default` logic.

## Prototype repo-owned asset and loader

This repo now includes a concrete prototype of the contract described above:

- `state/shelley-bridge-profiles.json`
- `py/shelley_bridge_profiles.py`
- `manage-shelley-bridge-profiles.sh`

Current prototype intent:

- make the contract executable instead of doc-only
- give the future cleaned Shelley runtime a concrete sample input shape
- give installer-side work a narrow validator/reader to evolve against

Current prototype behavior:

- `./manage-shelley-bridge-profiles.sh validate`
  - validates top-level schema/contract versions and profile names
- `./manage-shelley-bridge-profiles.sh resolve`
  - resolves the default profile from the prototype state file
- `./manage-shelley-bridge-profiles.sh resolve --profile-name NAME`
  - resolves a named profile

Current validation checks include:

- profile state file exists and is valid JSON
- supported `schema_version`
- supported `bridge_contract_version`
- requested profile exists and is enabled
- `bridge_path` is absolute, exists, and is executable
- `config_path` is absolute, exists, and is readable
- `base_url` parses as an absolute `http` or `https` URL
- `args` is a list of literal strings

Current limitation:

- the prototype sample still targets the validated disposable local bed values in this repo/VM
- that is intentional for now so the contract can be exercised immediately
- later installer-managed deployment work should rewrite the profile file to stable deployed paths such as `/opt/...` and a machine-local state location when appropriate
