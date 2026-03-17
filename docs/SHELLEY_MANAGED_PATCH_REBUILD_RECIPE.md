# Shelley managed S1 patch + rebuild recipe

## Purpose

Define the first concrete operational recipe for reproducing the validated S1 Shelley Stavrobot-mode patch shape in a managed, repeatable way.

This document is the bridge between:

- the validated disposable S1 spike in `/tmp/shelley-official`
- the managed rebuild contract in this repo
- an eventual installer-driven Shelley refresh path

It is intentionally practical and command-oriented.

## What this recipe is for

This recipe is for the first managed implementation of:

- optional per-conversation Shelley Stavrobot mode
- branch above Shelley's normal provider/model layer
- canonical bridge invocation through `shelley-stavrobot-bridge.sh`
- conversation-scoped remote mapping persistence in `conversation_options`

It is not the recipe for:

- S2 rich structured output fidelity
- advanced Shelley UI polish
- model-control admin UI
- recall/retrieval features

## Recommended managed checkout location

Recommended default managed checkout path:

- `/opt/shelley`

Recommended built binary path:

- `/opt/shelley/bin/shelley`

Why `/opt/shelley` is the right default:

- consistent with the project’s earlier installer-oriented expectations
- clearly separate from this repo
- appropriate for a machine-managed upstream checkout/build target
- avoids confusing the main repo with the rebuilt Shelley source tree

If `/opt/shelley` is not suitable in a specific environment, the installer can later make this configurable. But the managed recipe should pick one default and stay consistent.

## Required upstream inputs

Managed rebuild state should record at least:

- Shelley upstream repo URL
- Shelley branch
- Shelley upstream commit used
- managed patch shape/version
- bridge contract version
- local checkout path
- binary path

## Exact official Shelley files owned by the managed S1 patch

Based on the validated disposable spike, the managed S1 patch should own these official-Shelley files:

1. `db/db.go`
   - extend `ConversationOptions`
   - add `StavrobotOptions`
   - add Stavrobot mode detection helper(s)

2. `db/query/conversations.sql`
   - add `UpdateConversationOptions`

3. `db/generated/conversations.sql.go`
   - generated sqlc output after query change

4. `ui/src/types.ts`
   - extend frontend API typing for Stavrobot-capable `conversation_options`

5. `server/convo.go`
   - add helper/accessor methods for Stavrobot mode and mapping persistence

6. `server/handlers.go`
   - branch new-conversation and chat-conversation routes above ordinary provider layer
   - invoke focused Stavrobot runtime integration path
   - reuse message persistence and working-state behavior

## Recommended managed code-ownership boundary inside Shelley

Even though the disposable spike put most runtime logic directly into `server/handlers.go`, the managed patch should prefer a cleaner shape:

- keep route branching in handler/runtime layer
- move bridge/profile/runtime details into a focused Shelley-side Stavrobot integration unit if practical

But for S1, the patch still conceptually owns the same upstream layers listed above.

## Recommended patch application strategy

## Rule: do not treat `/tmp/shelley-official` as production source

The disposable spike is reference material only.

Managed rebuild should reproduce the validated patch shape from this repo’s owned recipe/patch material, not by copying the disposable checkout wholesale.

## Preferred strategy

Use an installer-owned patch set or scripted patch application against a clean/updatable upstream checkout.

Good options later:

- checked-in patch files under this repo
- scripted text edits owned by this repo
- a small maintained branch/worktree strategy if operationally simpler

Current recommendation:

- treat this recipe as the source of truth for what must be applied
- later automation should apply a deterministic local patch set from this repo

## Fetch/update recipe for official Shelley

Initial checkout:

```bash
sudo mkdir -p /opt
sudo git clone https://github.com/exe-dev/shelley.git /opt/shelley
```

Refresh existing checkout:

```bash
cd /opt/shelley
git fetch origin
git checkout main
git pull --ff-only origin main
```

Record upstream commit:

```bash
cd /opt/shelley
git rev-parse HEAD
git rev-parse --short HEAD
```

## Build prerequisites discovered in the disposable spike

The following build constraints were validated in the disposable official checkout:

1. frontend assets must exist under `ui/dist`
2. sqlc code must be regenerated when SQL changes
3. template artifacts must exist before final binary build

Concretely, the managed rebuild path should expect to run:

- UI dependency install if needed
- UI build
- sqlc regeneration when patch changes SQL
- template generation
- final Go build

## Exact rebuild command recipe

Assuming the managed patch has already been applied to `/opt/shelley`:

### 1. Regenerate sqlc output if SQL changed

```bash
cd /opt/shelley
go tool github.com/sqlc-dev/sqlc/cmd/sqlc generate -f sqlc.yaml
```

### 2. Build UI assets

Preferred current upstream path:

```bash
cd /opt/shelley/ui
pnpm install
pnpm run build
```

If the environment standardizes on npm in practice, the later automation can adapt. But current upstream guidance strongly points to `pnpm`.

### 3. Build template artifacts

```bash
cd /opt/shelley
make templates
```

### 4. Build Shelley binary

```bash
cd /opt/shelley
go build -o bin/shelley ./cmd/shelley
```

## Optional combined rebuild shorthand

Once the environment is known good, a managed flow can conceptually treat rebuild as:

```bash
cd /opt/shelley
go tool github.com/sqlc-dev/sqlc/cmd/sqlc generate -f sqlc.yaml
cd ui && pnpm install && pnpm run build
cd .. && make templates && go build -o bin/shelley ./cmd/shelley
```

But stepwise execution is easier to diagnose and is preferable for first implementation.

## Recommended Shelley bridge/profile integration rule for managed S1

The managed S1 patch must not keep the disposable spike’s hardcoded local profile mapping.

Instead, the Shelley-side managed patch should resolve bridge/profile data from installer-owned local state.

At minimum the managed runtime path must be able to determine:

- canonical bridge script path
- selected bridge profile name from conversation metadata
- machine-local profile definition for that name
- Stavrobot base URL
- Stavrobot config path
- optional default args such as stateless mode

The patch should still call only:

- `shelley-stavrobot-bridge.sh`

Lower-level wrappers remain out of Shelley's direct contract.

## Minimum post-build smoke validation recipe

These are the minimum validation steps the managed rebuild should perform after build.

## A. Binary sanity

```bash
cd /opt/shelley
./bin/shelley serve -h
```

Expected:

- binary runs
- serve flags print normally

## B. Isolated disposable run

Use a dedicated test port and DB so the user’s existing Shelley runtime is not disturbed.

Example validated-safe pattern:

```bash
cd /opt/shelley
./bin/shelley \
  -predictable-only \
  -default-model predictable \
  -model predictable \
  -db /tmp/shelley-stavrobot-managed-test.db \
  serve -port 8765 -socket none
```

Recommended execution wrapper later:

- run in tmux or controlled service process for testing
- do not collide with ports already in use by live services

## C. Normal Shelley control conversation

Validate ordinary Shelley behavior still works by creating a normal conversation with no Stavrobot metadata.

Expected:

- conversation creation succeeds
- normal predictable-model path still works

## D. Stavrobot-mode conversation create

Create a conversation using Stavrobot conversation options similar to:

```json
{
  "message": "Reply with exactly: managed spike first turn ok",
  "conversation_options": {
    "type": "stavrobot",
    "stavrobot": {
      "enabled": true,
      "bridge_profile": "local-default"
    }
  }
}
```

Expected:

- Shelley accepts conversation create
- user message is recorded
- assistant reply appears in normal Shelley message flow
- conversation metadata is updated with remote `conversation_id` and `last_message_id`

## E. Stavrobot continuation turn

Send a second message to the same Shelley conversation.

Expected:

- same remote Stavrobot `conversation_id` is reused
- `last_message_id` advances
- assistant reply is recorded normally

## F. Conversation metadata verification

Check stored conversation metadata and confirm shape similar to:

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

Important:

- no secrets in metadata
- only profile name, not raw local credentials/config blob

## Suggested HTTP smoke command flow

For a future automated smoke script, the managed flow can use roughly:

1. `POST /api/conversations/new` for normal conversation
2. `POST /api/conversations/new` for Stavrobot conversation
3. `GET /api/conversation/:id` to inspect message flow
4. `POST /api/conversation/:id/chat` for continuation turn
5. optional SQLite verification of `conversation_options`

## Minimum go/test validation before runtime smoke

Before live runtime smoke, run at least:

```bash
cd /opt/shelley
go test ./server/...
go test ./db/...
```

Why these are the minimum:

- they covered the primary compile/test surfaces touched by the disposable spike
- they are fast enough to be realistic in a managed refresh path

## Recommended rebuild-state updates after a successful smoke pass

After successful build + smoke validation, update installer-managed state with at least:

- upstream repo URL
- upstream branch
- upstream commit
- patch shape = `s1-per-conversation-stavrobot`
- patch version
- bridge contract version
- checkout path = `/opt/shelley`
- binary path = `/opt/shelley/bin/shelley`
- UI built = true
- templates built = true
- rebuilt timestamp
- default profile name
- available profile names
- last check timestamp
- rebuild required = false

## Failure policy for the managed rebuild recipe

Hard fail on:

- inability to fetch/update upstream Shelley checkout
- inability to apply managed patch set cleanly
- sqlc generation failure
- UI build failure
- template generation failure
- Go build failure
- minimum Go test failure
- inability to start isolated Shelley test binary
- failure of normal control conversation
- failure of Stavrobot first-turn or second-turn validation

Soft warn on:

- non-critical log noise from unrelated Shelley features
- optional richer-content fidelity not yet implemented in S1

## Important S1 cleanup constraints carried forward

Even in the managed rebuild, keep these constraints:

- preserve default Shelley behavior when Stavrobot mode is off
- keep per-conversation metadata small and secret-free
- keep bridge/profile resolution outside conversation metadata
- keep lower-level Stavrobot wrappers out of Shelley's direct contract
- do not over-assume S2 rich output behavior yet

## Recommended next implementation step after this recipe

The next practical move after this document is to create the actual managed patch material owned by this repo, such as:

- checked-in patch files for official Shelley
- or scripted patch application helpers
- plus a single smoke-test driver script that performs the minimum validation flow above

That would convert this recipe into a real repeatable rebuild/update path.


## Repo-owned first implementation assets

This repo now also contains first owned assets that map directly to this recipe:

- `patches/shelley/s1-stavrobot-mode-disposable-shape.patch`
- `smoke-test-shelley-managed-s1.sh`

Current role of each:

### `patches/shelley/s1-stavrobot-mode-disposable-shape.patch`

- captures the validated disposable S1 upstream diff shape from `/tmp/shelley-official`
- serves as a concrete starting artifact for the managed patch set
- should still be treated as a starting point, not as the final cleaned managed patch implementation

### `smoke-test-shelley-managed-s1.sh`

- launches an isolated Shelley binary on a safe test port
- validates a normal Shelley control conversation
- validates Stavrobot-mode first turn
- validates Stavrobot-mode continuation turn
- validates persisted `conversation_options` remote mapping metadata

So the project now has both the operational recipe and first repo-owned assets that can evolve into the actual managed rebuild/update path.
