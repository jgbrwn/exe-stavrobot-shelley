# Shelley managed rebuild contract

## Purpose

Define the concrete repeatable contract for turning the validated S1 disposable Shelley spike into an installer-managed local rebuild flow.

This document is intentionally about **managed rebuild mechanics**, not broader Shelley/Stavrobot product design.

It answers:

- what local state this repo should own
- what files/paths should exist
- how bridge profiles should be represented
- how refresh/staleness should be decided
- what future installer flags should do

## Scope

This contract is for the first managed implementation path of:

- optional Shelley rebuild with Stavrobot-capable S1 patch shape
- optional per-conversation Stavrobot mode inside that rebuilt Shelley
- installer-owned machine-local bridge profile resolution

It is **not** yet the implementation of:

- S2 structured media/tool/HTML fidelity
- advanced UI polish
- recall/retrieval workflows
- production-grade packaging for every environment

## Core contract

### 1. This repo owns rebuild state

Machine-local Shelley rebuild facts should live in this repo, not in Shelley conversation metadata.

### 2. Shelley conversations own only conversation-scoped mode metadata

Per-conversation Shelley metadata should remain small and secret-free, e.g.:

```json
{
  "type": "stavrobot",
  "stavrobot": {
    "enabled": true,
    "conversation_id": "conv_1",
    "last_message_id": "msg_110",
    "bridge_profile": "local-default"
  }
}
```

### 3. Bridge profiles are installer-managed named local configs

`bridge_profile` is just a name.

The installer-owned rebuild state resolves that name into machine-local facts such as:

- bridge script path
- Stavrobot config path
- Stavrobot base URL
- optional execution defaults

### 4. Shelley rebuilds must be repeatable from upstream + local patch version

A managed rebuild must be able to say:

- which Shelley upstream commit it was built from
- which local Stavrobot-mode patch/rebuild contract version it used
- which bridge profiles were available at build/refresh time

## Recommended managed file layout

Within this repo:

```text
state/
  shelley-mode-build.json
  shelley-bridge-profiles.json
  shelley-upstream/
    README.md                    # optional operator note later
    .gitkeep                     # until real automation exists
```

Recommended meanings:

- `state/shelley-mode-build.json`
  - rebuild provenance and current status facts
- `state/shelley-bridge-profiles.json`
  - named local bridge profile definitions
- `state/shelley-upstream/`
  - optional managed checkout/worktree location for official Shelley source later

Current repo-owned helper coverage now includes:

- `validate-shelley-patch-series.sh` for replay/apply + build/test validation against a fresh upstream checkout
- `refresh-shelley-managed-s1.sh` for managed checkout patch/rebuild/smoke refreshes plus state-file updates
- `print-shelley-managed-status.sh` for the read-only configured/current/stale/rebuild-required view described below

## State file 1: rebuild provenance

Recommended file:

- `state/shelley-mode-build.json`

Recommended shape:

```json
{
  "schema_version": 1,
  "mode": "stavrobot",
  "enabled": true,
  "managed_at": "2025-01-01T00:00:00Z",
  "upstream": {
    "repo": "https://github.com/exe-dev/shelley.git",
    "branch": "main",
    "commit": "abcdef1234567890",
    "commit_short": "abcdef1"
  },
  "local_contract": {
    "patch_shape": "s1-per-conversation-stavrobot",
    "patch_version": 1,
    "bridge_contract_version": 1
  },
  "build": {
    "checkout_path": "/opt/shelley",
    "binary_path": "/opt/shelley/bin/shelley",
    "ui_built": true,
    "templates_built": true,
    "rebuilt_at": "2025-01-01T00:00:00Z"
  },
  "profiles": {
    "default": "local-default",
    "available": ["local-default"]
  },
  "status": {
    "upstream_stale": false,
    "profiles_stale": false,
    "rebuild_required": false,
    "last_check_at": "2025-01-01T00:00:00Z"
  }
}
```

### Required meaning of fields

- `schema_version`
  - version of this installer-owned file format
- `mode`
  - currently `stavrobot`
- `enabled`
  - whether a managed Shelley mode build is currently intended/present
- `upstream.*`
  - provenance of the Shelley source used
- `local_contract.patch_shape`
  - human-readable identifier for the validated integration family
- `local_contract.patch_version`
  - local version of the managed Shelley patch set
- `local_contract.bridge_contract_version`
  - expected bridge IO contract version
- `build.checkout_path`
  - managed or referenced Shelley source tree
- `build.binary_path`
  - built Shelley binary path
- `profiles.default`
  - default bridge profile name to suggest/use later
- `profiles.available`
  - profile names known at last refresh/build
- `status.*`
  - cached staleness/status summary for read-only reporting

## State file 2: bridge profile definitions

Recommended file:

- `state/shelley-bridge-profiles.json`

Recommended shape:

```json
{
  "schema_version": 1,
  "bridge_contract_version": 1,
  "profiles": {
    "local-default": {
      "enabled": true,
      "bridge_path": "/home/exedev/exe-stavrobot-shelley/shelley-stavrobot-bridge.sh",
      "base_url": "http://localhost:8000",
      "config_path": "/opt/stavrobot/data/main/config.toml",
      "args": ["--stateless"],
      "notes": "Local default Stavrobot instance"
    }
  },
  "default_profile": "local-default",
  "updated_at": "2025-01-01T00:00:00Z"
}
```

### Required profile rules

Each profile definition should:

- contain no raw secrets
- resolve to the canonical `shelley-stavrobot-bridge.sh`
- include enough machine-local config to let Shelley invoke the bridge safely
- be independently replaceable without rewriting Shelley conversations

### Explicit non-goals for profile state

Do not store in conversation metadata:

- API keys
- raw auth passwords
- full mutable machine config blobs
- transient remote conversation IDs for unrelated conversations

## Source of truth rules

### Conversations

Source of truth for:

- whether a specific conversation is in Stavrobot mode
- remote `conversation_id` for that conversation
- remote `last_message_id` for that conversation
- selected `bridge_profile` name for that conversation

### Installer-managed state

Source of truth for:

- where Shelley upstream source/binary lives locally
- which upstream Shelley commit was used
- which managed patch contract version is installed
- which bridge profiles exist and how they resolve locally
- whether rebuild/refresh appears stale

## Recommended refresh algorithm

## Read-only status check

Equivalent future behavior of:

```bash
./install-stavrobot.sh --print-shelley-mode-status
```

Algorithm:

1. read `state/shelley-mode-build.json`
2. read `state/shelley-bridge-profiles.json`
3. verify referenced profile names still exist
4. verify bridge script path exists
5. verify configured Shelley checkout/binary paths exist
6. inspect managed Shelley checkout HEAD if available
7. compare current upstream/checkout commit to recorded `upstream.commit`
8. compare profile names + contract versions to recorded values
9. print status summary:
   - configured / not configured
   - upstream current / current-dirty / stale / unknown
   - profiles current / stale / missing
   - rebuild likely required / not required

Current repo-owned helper for this path:

- `print-shelley-managed-status.sh`
- installer entrypoint: `./install-stavrobot.sh --print-shelley-mode-status`
- machine-readable installer entrypoint: `./install-stavrobot.sh --print-shelley-mode-status --json`

## Refresh / rebuild check

Equivalent future behavior of:

```bash
./install-stavrobot.sh --refresh-shelley-mode
```

Algorithm:

1. load both state files
2. validate schema versions
3. validate that default profile exists
4. update or fetch Shelley upstream checkout
5. detect upstream HEAD commit
6. compare against recorded `upstream.commit`
7. compare managed patch version expected by this repo vs recorded `patch_version`
8. compare bridge contract version expected by this repo vs recorded `bridge_contract_version`
9. compare resolved profile definitions vs recorded available/default profiles
10. decide whether rebuild is required
11. if rebuild required:
    - build Shelley UI if needed
    - build Shelley templates if needed
    - apply/reapply managed S1 patch shape
    - rebuild Shelley binary
    - run minimum validation checks
12. write updated `state/shelley-mode-build.json`
13. write updated `profiles.available` snapshot
14. print final status and next steps

## Force rebuild

Equivalent future behavior of:

```bash
./install-stavrobot.sh --force-shelley-rebuild
```

Same as refresh, except staleness heuristics are bypassed and rebuild steps run regardless.

## Disable mode bookkeeping

Equivalent future behavior of:

```bash
./install-stavrobot.sh --disable-shelley-mode
```

Recommended behavior:

- do not rewrite user conversations
- do not delete Shelley upstream checkout by default
- mark managed Shelley mode as disabled in rebuild state
- optionally stop advertising profiles as active
- print operator-facing consequences clearly

## Minimal rebuild validation after refresh

A managed refresh should at least verify:

1. Shelley builds successfully
2. expected Stavrobot-capable patch points are present
3. bridge profile file is readable
4. canonical bridge path exists and is executable
5. a normal Shelley conversation path still exists conceptually
6. a Stavrobot conversation can be configured with a valid `bridge_profile`

Later implementation can add deeper automated validation.

## Future installer flag contract

Recommended explicit flags:

### `--with-shelley-stavrobot-mode`

Intent:

- opt into Shelley-aware rebuild/update work during a normal installer run

Recommended behavior:

- initialize state files if missing
- ensure at least one bridge profile exists
- ensure managed Shelley checkout exists
- rebuild if stale or missing

### `--refresh-shelley-mode`

Intent:

- run Shelley mode refresh logic explicitly, even when normal Stavrobot install work would not require it

Recommended behavior:

- use stored state
- fail clearly if state is malformed or missing required fields
- refresh checkout/profile/build state

Current repo-owned helper for this path:

- `refresh-shelley-managed-s1.sh`
- installer entrypoint: `./install-stavrobot.sh --refresh-shelley-mode`

### `--print-shelley-mode-status`

Intent:

- safe read-only status inspection

Recommended behavior:

- no mutation
- no implicit checkout change
- no implicit rebuild
- clear stale/current/missing summary

### `--force-shelley-rebuild`

Intent:

- force rebuild regardless of staleness heuristics

Recommended behavior:

- still validate state and profile existence
- still record fresh provenance afterward

### `--disable-shelley-mode`

Intent:

- disable managed Shelley mode bookkeeping cleanly

Recommended behavior:

- should not silently destroy local Shelley state
- should not touch per-conversation metadata

## Recommended conflict rules

Installer should fail fast on combinations like:

- `--with-shelley-stavrobot-mode` + `--disable-shelley-mode`
- `--print-shelley-mode-status` + any mutating Shelley flag
- `--refresh-shelley-mode` + incompatible normal installer mutation flags
- status-only Shelley flags mixed with rebuild-only Shelley flags

Current installer behavior now enforces these guardrails explicitly:

- `--print-shelley-mode-status` rejects normal installer mutation flags and Shelley refresh-only flags
- `--refresh-shelley-mode` rejects `--stavrobot-dir` and normal installer mutation flags
- `--allow-dirty-shelley` and `--skip-shelley-smoke` require `--refresh-shelley-mode`

## Patch versioning recommendation

This repo should track the managed S1 rebuild target as an explicit local contract version.

Initial recommendation:

- `patch_shape = "s1-per-conversation-stavrobot"`
- `patch_version = 1`
- `bridge_contract_version = 1`

Bump:

- `patch_version` when managed Shelley-side patch behavior changes materially
- `bridge_contract_version` when the bridge IO contract changes materially
- `schema_version` when installer-owned state file format changes materially

## Relationship to S2 and later

This managed rebuild contract is intentionally S1-focused.

That means:

- it should support text-first validated operation now
- it should not block later richer structured output
- it should preserve room for later message adaptation improvements

Likely later additions, but not required now:

- richer bridge output capability declarations
- media/image handling configuration
- tool/display event adaptation toggles
- HTML-safe rich content handling metadata
- history/event reconciliation settings

## Immediate next implementation artifact after this document

That concrete operational recipe now lives in:

- `docs/SHELLEY_MANAGED_PATCH_REBUILD_RECIPE.md`

It describes:

- where the official Shelley checkout should live
- exact fetch/update/build commands
- exact patch application strategy
- minimum smoke validation commands
- what files in official Shelley the managed S1 patch owns


## Related but separate future feature: Stavrobot backend model control

A future Shelley-side control for changing the shared Stavrobot backend model should be treated as:

- available only from Stavrobot mode context
- separate from per-conversation routing metadata
- backed by an installer-managed local helper/service boundary

It should not be modeled as ordinary upstream Shelley behavior, and it should not imply that backend model choice is per-conversation unless Stavrobot later supports that natively.

See:

- `docs/SHELLEY_STAVROBOT_MODEL_CONTROL.md`


## Live deployment/cutover note

When the managed Shelley rebuild is eventually deployed onto the target VM's real Shelley runtime, the installer should treat binary replacement as a separate cutover phase.

At minimum that phase should handle:

- stop `shelley.socket`
- stop `shelley.service`
- preserve a one-time backup of the original `/usr/local/bin/shelley`
- install the rebuilt binary to `/usr/local/bin/shelley`
- start `shelley.socket`
- start `shelley.service`
- validate live service health afterward

This is separate from the isolated build/smoke validation phase and should be recorded in installer-managed deployment state rather than in conversation metadata.


## Bridge profile resolution contract note

The concrete narrow contract the cleaned Shelley patch should use for installer-managed bridge profile lookup now lives in:

- `docs/SHELLEY_BRIDGE_PROFILE_RESOLUTION_CONTRACT.md`

That contract narrows the Shelley-side dependency to:

- profile-name lookup
- bridge-path resolution
- base URL resolution
- config-path resolution
- installer-managed default argv resolution
