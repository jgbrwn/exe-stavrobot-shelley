# Shelley ↔ Stavrobot MVP plan

## Goal

Define the smallest useful Shelley integration path for Stavrobot on exe.dev without requiring immediate upstream Stavrobot changes.

## Constraints discovered so far

1. Stavrobot already exposes a stable-enough authenticated HTTP chat endpoint at `POST /chat`.
2. That endpoint accepts:
   - `message`
   - optional `source`
   - optional `sender`
   - optional attachments/files
3. It returns JSON containing `response`.
4. Stavrobot also exposes authenticated settings/plugin endpoints that the installer already uses.
5. There is currently no dedicated conversation-history/events API designed for Shelley.
6. There is no explicit "Shelley mode" in Stavrobot today.

## Recommended MVP

Phase 2 Shelley work should start with a thin adapter instead of upstream modifications.

### MVP shape

Add a local helper entrypoint in this repo:
- `chat-with-stavrobot.sh`

Purpose:
- act as the narrow compatibility layer between Shelley and a running Stavrobot instance
- read Stavrobot auth from `config.toml`
- send a prompt to `/chat`
- print the assistant response to stdout

### Why this is the right first move

- It uses existing Stavrobot behavior.
- It avoids speculative upstream API design.
- It gives Shelley a concrete integration surface immediately.
- It is easy to test locally and easy to replace later.

## Proposed Shelley integration flow

1. Operator deploys Stavrobot with `install-stavrobot.sh`.
2. Operator validates email worker/manual integrations as needed.
3. Shelley invokes `chat-with-stavrobot.sh` with:
   - `--stavrobot-dir /path/to/stavrobot`
   - `--message ...`
4. The adapter posts to Stavrobot `/chat` using Basic Auth from config.
5. The adapter prints only the assistant response by default.

## MVP limitations

- No streaming output yet.
- No first-class conversation/session controls beyond what Stavrobot already does internally.
- No history sync into Shelley.
- No structured tool/event trace surfaced back to Shelley.
- No attachment bridging beyond raw `/chat` support.

## Likely next upstream asks after MVP

If Shelley proves valuable as a frontend, the next likely Stavrobot API additions would be:

1. Real conversation/session identifiers for `/api/client/chat`
2. Read-only conversation listing endpoint
3. Read-only conversation/history endpoint
4. Read-only events or traces endpoint later if needed
5. Health/status endpoint richer than basic auth page checks
6. A stable machine-oriented API namespace distinct from the current web UI endpoints

## What Phase 2 testing has now validated

Phase 2 testing has now moved beyond pure planning:

- additive upstream `GET /api/client/health` and `POST /api/client/chat` were successfully spiked in a separate upstream test clone
- a real live LLM-backed response was confirmed through `POST /api/client/chat`
- Stavrobot worked with provider `openrouter` without needing an OpenRouter-specific patch
- the successful live model used in testing was `z-ai/glm-4.5-air:free`
- the upstream spike now also includes real `conversation_id` support
- the upstream spike now also includes conversation listing and conversation history endpoints
- a live runtime pass then confirmed the rebuilt stack could return `conv_1`, list that conversation, fetch its messages, and continue the same conversation on a second chat turn
- the next upstream increment was completed too: `GET /api/client/conversations/:conversation_id/events` now returns read-only tool-call/tool-result events and was also live-validated
- real chat `message_id` support was then completed too: `POST /api/client/chat` now returns a real assistant message ID that matches persisted history

That means the additive `/api/client/*` direction is now materially validated both in the spike and in a live running stack, including event visibility and real chat message IDs. The next likely work is just incremental client ergonomics if Shelley needs them.

The main repo now has a recommended canonical Shelley-facing bridge plus lower-level helpers:

- `shelley-stavrobot-bridge.sh` as the canonical Shelley-facing bridge for future rebuild/integration work
- `chat-with-stavrobot.sh` as the lowest-risk existing `/chat` fallback
- `client-stavrobot.sh` as the validated lower-level `/api/client/*` wrapper
- `shelley-stavrobot-session.sh` as the lower-level stateful wrapper that persists and reuses the last `conversation_id`

That gives Shelley one preferred integration target while still preserving lower-level tools for debugging, smoke tests, and manual operator use.

## Decision

Start Shelley integration with the adapter script first.
Do not block on upstream Stavrobot changes.

## Original rebuild intent and current alignment

The original intent for a future Shelley rebuild was not to permanently turn Shelley into Stavrobot. It was to add an optional Shelley "Stavrobot mode" while preserving normal Shelley behavior when that mode is not enabled.

What we have learned since then fits that intent well:

- Shelley should not need to know every helper script individually.
- Shelley should target one canonical local integration surface.
- That canonical surface is now `shelley-stavrobot-bridge.sh`.
- Lower-level scripts remain useful for debugging, smoke tests, and manual operator workflows.
- The existing `chat-with-stavrobot.sh` path remains a conservative fallback.

That means the next actual rebuild step should look like this:

1. add an explicit optional Shelley "Stavrobot mode"
2. keep existing Shelley behavior unchanged when that mode is off
3. when the mode is on, have Shelley invoke `shelley-stavrobot-bridge.sh`
4. keep the lower-level wrappers out of Shelley's primary integration contract

In other words, the bridge/wrapper work did not change the original intent. It clarified how to implement that intent cleanly.

## Adapter hardening notes

The first adapter hardening pass should prefer local improvements before upstream changes:

- configurable base URL
- configurable connect/request timeouts
- retry behavior for transport failures
- raw JSON debug mode
- stdin support for piping prompts from other tools
- a local machine-oriented client wrapper for validated `/api/client/*` endpoints
- a small Shelley-side state file for last conversation reuse
- terse extraction flags so Shelley can request only `response`, `conversation_id`, or `message_id` when needed
- a smoke harness that checks health, chat, conversation listing, history, and events together

These are now implemented across `chat-with-stavrobot.sh`, `client-stavrobot.sh`, `shelley-stavrobot-session.sh`, and `smoke-test-stavrobot-client.sh`.

## Next planning artifact

The proposed additive upstream API surface is documented in:

- `docs/STAVROBOT_UPSTREAM_API_PROPOSAL.md`

## Installer wiring implications

Even though the optional runtime mode likely belongs in Shelley proper, the rebuild/update orchestration can still live in this repo.

That means the installer and rebuild story should eventually converge like this:

1. `install-stavrobot.sh` remains the normal default path for Stavrobot deployment/update.
2. A later optional installer path can enable or refresh Shelley "Stavrobot mode".
3. That installer path should fetch or update Shelley from its upstream repo, rebuild it, and record the upstream Shelley commit/hash it was built from.
4. That recorded upstream hash should let the installer tell whether the locally rebuilt Shelley variant is already current or needs refresh.
5. When optional Shelley mode is requested, the rebuilt Shelley variant should call only `shelley-stavrobot-bridge.sh` for Stavrobot interaction.
6. The installer should not duplicate lower-level client/session logic that already lives behind the canonical bridge.

So the bridge/wrapper work is not drifting away from the installer plan. It is defining the stable local contract that the future installer-assisted Shelley rebuild should consume.

## Rich output implications

Shelley is especially strong at presenting markdown and screenshots natively. That should influence the eventual mode design.

Implications:

1. The integration should preserve markdown-friendly response text rather than flattening it unnecessarily.
2. The canonical bridge should remain capable of returning structured data when Shelley needs more than plain response text.
3. Screenshot or image-oriented workflows should be treated as first-class future integration needs rather than an afterthought.
4. The bridge/wrapper layer should avoid overfitting around plain-text-only output if Shelley can productively render richer results.

That does not immediately require a new upstream Stavrobot API change, but it does mean future Shelley-side mode work should prefer preserving structured responses and screenshot references where practical.

## Likely Shelley-side implementation seam

A deeper disposable inspection of the official Shelley repo suggests the cleanest future integration seam is above the LLM model layer, not inside it.

Why:

- Shelley's existing model layer is for true LLM providers and custom model endpoints.
- Stavrobot is not just another raw model endpoint; it is a higher-level agent service with conversation/history/events behavior.
- Shelley already has a richer message/content model, display data, and multi-modal handling than a plain text transport wrapper would imply.

So the most plausible future Shelley implementation shape is:

1. add an optional Shelley-side conversation/runtime mode such as "Stavrobot mode"
2. keep normal direct-to-LLM conversations unchanged
3. when Stavrobot mode is enabled for a conversation or server instance, route user turns through `shelley-stavrobot-bridge.sh`
4. map the returned Stavrobot data into Shelley's own message/display structures rather than pretending Stavrobot is merely a model provider

This is especially important because Shelley already has meaningful native support for:

- markdown-friendly rendering
- screenshots and image content
- tool/display metadata
- conversation streaming/state infrastructure

That means the eventual Shelley-side implementation should aim to preserve rich content opportunities instead of squeezing everything through a fake model abstraction too early.

## Server-wide vs per-conversation mode

After inspecting the official Shelley repo more deeply, per-conversation mode now looks like the cleaner likely target.

Why per-conversation mode fits better:

1. Shelley already stores extensible `conversation_options` JSON on each conversation.
2. Shelley already treats conversations as durable first-class objects with their own state and metadata.
3. A per-conversation mode preserves normal Shelley behavior in other conversations without needing a whole separate Shelley instance.
4. It maps naturally to a future UI toggle like "use Stavrobot for this conversation".

Why server-wide mode is still simpler but weaker:

- simpler to implement first
- easier to reason about operationally
- but forces one behavior for all conversations in that Shelley instance
- and fits Shelley's conversation-centric architecture less well

Current recommendation:

- long-term preferred shape: per-conversation optional Stavrobot mode
- possible first spike shape: server-wide mode if that is materially easier to validate
- but even a server-wide spike should be evaluated as a stepping stone toward per-conversation mode, not necessarily the final shape

## Cross-conversation memory question

A good question is whether per-conversation mode would make Shelley too narrow: if one conversation is tied to one Stavrobot conversation, can Shelley still answer questions like "remember when we did X two weeks ago?"

Based on what we have validated so far, the answer is: potentially yes, but not automatically yet.

What the current validated Stavrobot surface already gives us:

- conversation listing
- conversation message history
- conversation events
- stable conversation IDs
- stable message IDs

What that means:

1. Per-conversation mode can cleanly preserve local continuity for an active thread.
2. Cross-conversation recall could be layered on top by searching/listing/selecting other Stavrobot conversations when needed.
3. That broader recall is conceptually different from ordinary within-thread continuation, so it should be treated as an additional memory/retrieval behavior, not assumed to happen for free.

Most likely practical design:

- normal per-conversation Stavrobot mode continues one mapped Stavrobot conversation
- when the user asks for older/global recall, Shelley may need an explicit retrieval step over Stavrobot conversation history
- that retrieval step could later use Stavrobot conversation listing/history and possibly message-content search if such ergonomics are added

Important caveat:

- the currently validated Stavrobot client surface includes listing and history retrieval, but not dedicated semantic/global memory search yet
- so "remember when we did X weeks ago" is feasible as a future retrieval workflow, but not something we should pretend is solved purely by per-conversation mode alone

That suggests the right mental model is:

- per-conversation mode handles active thread continuity
- cross-conversation recall is a separate memory/retrieval feature that can be layered on top later

## Minimal per-conversation metadata shape

Given Shelley's existing `conversation_options` extensibility, the minimal Shelley-side shape for optional Stavrobot mode should stay small and conversation-scoped.

Recommended minimum stored per Shelley conversation:

```json
{
  "mode": "stavrobot",
  "stavrobot": {
    "enabled": true,
    "conversation_id": "conv_123",
    "last_message_id": "msg_456",
    "bridge_profile": "local-default"
  }
}
```

Practical meaning of each field:

- `mode = "stavrobot"`
  - the conversation should route turns through the Stavrobot integration path rather than Shelley's ordinary direct model flow
- `stavrobot.enabled = true`
  - explicit boolean guard so Shelley can distinguish between stored historical metadata and active mode
- `stavrobot.conversation_id`
  - the mapped remote Stavrobot conversation for ordinary continuation
- `stavrobot.last_message_id`
  - optional sync/checkpoint hint for incremental history/event fetches and UI refresh behavior
- `stavrobot.bridge_profile`
  - stable local profile name, not raw credentials, describing which installer-managed bridge/base-url/auth bundle this conversation should use

Recommended non-goals for the minimal shape:

- do not store Stavrobot Basic Auth secrets inside Shelley conversation metadata
- do not store raw base URLs per conversation unless a later real multi-backend use case demands it
- do not overload the per-conversation mapping with cross-conversation memory state
- do not assume the metadata itself is the source of truth for all context; Stavrobot remains the source of truth for the mapped remote thread

A slightly richer but still reasonable optional shape later could add:

- `source`
- `sender`
- `last_history_sync_at`
- `last_event_sync_at`
- `retrieval_enabled`

But those should be treated as follow-on fields, not required for the first rebuild.

## Long-running conversation implication

A user absolutely could keep one Shelley conversation alive for a very long time.

That is not inherently a problem if the Shelley-side Stavrobot mode is implemented as a frontend mapping to a durable Stavrobot conversation rather than as a giant local prompt transcript that Shelley keeps resending to a model provider each turn.

Important distinction:

- Shelley UI conversation length is not automatically the same thing as direct LLM prompt length
- in Stavrobot mode, the durable active context should primarily live in Stavrobot's own conversation state and history
- Shelley should avoid needing to replay the full historical transcript through its normal direct-model path on every turn

So the context-pressure question changes:

- the main scaling concern is Stavrobot's own context/window and retrieval behavior
- not whether the Shelley conversation row has existed for months

That means Shelley's built-in context indicator should probably be treated carefully in Stavrobot mode:

- it may still be useful as a UI signal if Shelley can compute or estimate something meaningful
- but it should not pretend Shelley's ordinary direct-provider token accounting is the source of truth when Stavrobot owns the active context
- if Shelley cannot measure real Stavrobot context usage yet, the safest first version is to show a mode-specific indicator such as "external context managed by Stavrobot" rather than a fake precise gauge
- if a later Stavrobot API exposes usable context/window estimates, Shelley could then render a more meaningful mode-specific gauge

So: yes, one long-lived conversation is plausible, and no, that does not by itself imply Shelley becomes too slow, provided Shelley treats Stavrobot mode as remote conversation continuation rather than local transcript replay.


## Draft Shelley `conversation_options` shape

If the Shelley-side rebuild uses per-conversation metadata, the first practical contract could be represented in `conversation_options` roughly like this:

```json
{
  "mode": "stavrobot",
  "stavrobot": {
    "enabled": true,
    "conversation_id": "conv_123",
    "last_message_id": "msg_456",
    "bridge_profile": "local-default"
  }
}
```

Suggested field contract for the first version:

- `mode`
  - string
  - `"stavrobot"` enables the alternate runtime path
- `stavrobot.enabled`
  - boolean
  - explicit on/off flag for the conversation-scoped mode
- `stavrobot.conversation_id`
  - string
  - remote Stavrobot conversation ID such as `conv_123`
- `stavrobot.last_message_id`
  - string, optional
  - most recent known Stavrobot message ID such as `msg_456`
- `stavrobot.bridge_profile`
  - string
  - installer-managed local profile name used to resolve bridge/base-url/auth details outside the conversation record

Suggested validation rules:

- when `mode != "stavrobot"`, the `stavrobot` block may be absent or ignored
- when `mode == "stavrobot"`, require:
  - `stavrobot.enabled = true`
  - non-empty `stavrobot.bridge_profile`
- `stavrobot.conversation_id` may be absent for a brand new conversation before the first successful remote turn
- `stavrobot.last_message_id` is optional and should be treated as a hint, not the sole source of truth

Suggested lifecycle:

1. user creates or converts a Shelley conversation into Stavrobot mode
2. Shelley writes:
   - `mode = "stavrobot"`
   - `stavrobot.enabled = true`
   - `stavrobot.bridge_profile = "local-default"`
3. first successful bridge-mediated remote turn returns a real `conversation_id`
4. Shelley stores `stavrobot.conversation_id`
5. subsequent turns reuse that mapping
6. successful turns may update `stavrobot.last_message_id`

Suggested future-but-not-required extensions:

```json
{
  "mode": "stavrobot",
  "stavrobot": {
    "enabled": true,
    "conversation_id": "conv_123",
    "last_message_id": "msg_456",
    "bridge_profile": "local-default",
    "source": "shelley",
    "sender": "default",
    "last_history_sync_at": "2025-01-01T12:34:56Z",
    "last_event_sync_at": "2025-01-01T12:34:56Z",
    "retrieval": {
      "enabled": false,
      "mode": "explicit"
    }
  }
}
```

But the first rebuild should not require those extra fields.


## Installer CLI implication

The eventual installer-managed Shelley path should stay explicit and operational.

Recommended future commands should look roughly like:

```bash
./install-stavrobot.sh --with-shelley-stavrobot-mode --shelley-dir /opt/shelley
./install-stavrobot.sh --refresh-shelley-mode
./install-stavrobot.sh --print-shelley-mode-status
```

Important principle:

- the installer prepares the Shelley build and local bridge profiles
- Shelley itself should still own conversation-level mode selection and per-conversation metadata

So the installer should not directly rewrite user conversations. It should only make the optional Stavrobot-mode-capable Shelley build available and keep its local rebuild/profile state current.


## Draft Shelley conversation lifecycle for Stavrobot mode

The Shelley-side implementation should treat Stavrobot mode as a per-conversation runtime state machine rather than just a boolean toggle.

Recommended conversation states:

### 1. Normal

Meaning:

- ordinary Shelley conversation behavior
- no Stavrobot mapping in use

Typical metadata:

```json
{
  "mode": "default"
}
```

### 2. Stavrobot configured, not yet mapped

Meaning:

- the conversation has been switched into Stavrobot mode
- a bridge profile is selected
- no successful remote turn has yet created or confirmed a Stavrobot `conversation_id`

Typical metadata:

```json
{
  "mode": "stavrobot",
  "stavrobot": {
    "enabled": true,
    "bridge_profile": "local-default"
  }
}
```

Recommended UI cues:

- show that the conversation is in Stavrobot mode
- show selected local profile name
- show status like `Not yet connected to remote conversation`

### 3. Stavrobot mapped and active

Meaning:

- at least one successful remote turn has completed
- the conversation is now mapped to a durable Stavrobot `conversation_id`

Typical metadata:

```json
{
  "mode": "stavrobot",
  "stavrobot": {
    "enabled": true,
    "bridge_profile": "local-default",
    "conversation_id": "conv_123",
    "last_message_id": "msg_456"
  }
}
```

Recommended UI cues:

- show Stavrobot mode active
- show remote conversation connected
- optionally show remote conversation ID in debug/details view, not necessarily in the main user-facing thread chrome
- show mode-specific context wording such as `Context managed by Stavrobot`

### 4. Stavrobot degraded / attention-needed

Meaning:

- conversation metadata indicates Stavrobot mode
- but the current profile, bridge, auth, or remote session access has failed

Examples:

- missing bridge profile
- unreadable local config
- bridge execution failure
- remote auth failure
- remote conversation lookup/history fetch fails unexpectedly

Recommended UI cues:

- show clear non-destructive warning state
- do not silently fall back to normal direct-model mode for the same turn
- make the failure actionable: missing profile, bridge unavailable, auth failure, remote unavailable, etc.

## Recommended state transitions

### Transition A: normal -> Stavrobot configured

Trigger:

- user explicitly chooses Stavrobot mode for this conversation

Recommended effect:

1. Shelley validates that at least one installer-managed bridge profile exists
2. Shelley stores:
   - `mode = "stavrobot"`
   - `stavrobot.enabled = true`
   - `stavrobot.bridge_profile = <selected profile>`
3. Shelley does not require a remote conversation ID yet

If no local profile exists:

- fail the mode switch cleanly
- show guidance that Shelley Stavrobot mode is not installed/configured locally

### Transition B: configured -> mapped active

Trigger:

- first successful message sent through the canonical bridge

Recommended effect:

1. Shelley sends the user turn through `shelley-stavrobot-bridge.sh`
2. bridge/session layer creates a new remote Stavrobot conversation if needed
3. Shelley receives successful response data including `conversation_id`
4. Shelley persists:
   - `stavrobot.conversation_id`
   - `stavrobot.last_message_id` when available
5. Shelley renders the returned response in its normal message UI

If the first remote turn fails:

- remain in `configured, not yet mapped`
- do not invent a fake `conversation_id`
- keep the draft user turn/result/error semantics consistent with normal Shelley failure handling

### Transition C: mapped active -> mapped active

Trigger:

- subsequent successful user turn in Stavrobot mode

Recommended effect:

1. Shelley routes turn through the canonical bridge
2. bridge uses the existing mapped `conversation_id`
3. Shelley updates `last_message_id` if a newer one is returned
4. Shelley may optionally refresh history/events views separately

### Transition D: mapped active -> degraded

Trigger:

- existing Stavrobot conversation becomes temporarily unusable
- bridge/profile/config/auth/runtime error occurs

Recommended effect:

- preserve existing mapping metadata unless user explicitly resets/remaps
- show failure clearly
- allow retry after operator/user correction
- avoid silently remapping to a new remote conversation unless the user explicitly requested reset/new thread behavior

### Transition E: degraded -> mapped active

Trigger:

- operator or user fixes the underlying issue and a later turn succeeds

Recommended effect:

- reuse the same stored `conversation_id` when still valid
- clear degraded UI state
- continue ordinary mapped conversation flow

### Transition F: mapped active -> configured, not yet mapped

Trigger:

- user explicitly resets the remote mapping for this Shelley conversation

Recommended effect:

- keep `mode = "stavrobot"`
- keep selected `bridge_profile`
- clear:
  - `stavrobot.conversation_id`
  - `stavrobot.last_message_id`
- next successful turn creates a fresh remote conversation mapping

This is the clean "new remote thread, same Shelley conversation shell" operation.

### Transition G: Stavrobot mode -> normal mode

Trigger:

- user explicitly disables Stavrobot mode for the conversation

Recommended effect:

- Shelley stops routing turns through the bridge
- Shelley may either:
  - preserve prior `stavrobot` metadata as inactive historical info
  - or clear the `stavrobot` block except for an audit/debug trail if Shelley has a good reason to retain it
- this should be an explicit UX choice, not an automatic fallback after errors

## Recommended reset/remap semantics

There should be a clear distinction between:

### Reset remote mapping

- keep conversation in Stavrobot mode
- clear mapped remote `conversation_id`
- next turn starts a fresh Stavrobot thread

### Change bridge profile

- keep conversation in Stavrobot mode
- switch from one installer-managed profile name to another
- Shelley should warn that the existing remote mapping may not be valid against the new profile/backend
- safest default is to require or strongly suggest mapping reset when profile changes materially

### Disable Stavrobot mode

- stop using bridge path entirely for future turns in this conversation
- do not do this automatically on transient failures

## Recommended message/history/event handling

For the first version, Shelley should keep the send-turn path and the history/event sync path conceptually separate.

### Send-turn path

- send user turn through canonical bridge
- render assistant response normally
- update mapping metadata from returned IDs

### History/event path

Optional at first, but likely useful later:

- fetch remote message history when Shelley needs reconciliation/debug/history refresh
- fetch remote events when Shelley wants richer trace/tool views
- treat `last_message_id` as a sync hint, not as proof that local and remote are perfectly synchronized

That separation reduces coupling and makes failures easier to reason about.

## Recommended UI wording for context and recall

For active context in Stavrobot mode:

- prefer wording like `Context managed by Stavrobot`
- avoid pretending Shelley's ordinary direct-model token gauge is authoritative

For broader recall:

- treat `remember when we did X?` as a separate retrieval action/state
- likely initial UX should be explicit, not magical
- e.g. Shelley may show that it is searching or loading older Stavrobot conversations/history before answering

## Recommended edge-case behavior

### Missing installer-managed profile

- keep conversation metadata intact
- show actionable error
- do not silently switch providers/modes

### First turn succeeds but metadata write fails

- show response if possible
- warn that remote mapping may not be persisted
- next turn may require reconciliation or explicit remap handling

### Stored `conversation_id` no longer works

- enter degraded state
- offer explicit options such as:
  - retry
  - reset remote mapping
  - switch profile
  - disable Stavrobot mode

### Multiple long-lived months-long conversations

- acceptable in principle
- performance concern should focus on bridge/remote behavior and sync ergonomics, not merely the number of Shelley conversation records

## Recommended first implementation discipline

For the earliest Shelley-side spike, keep the state machine minimal:

- normal
- configured, not yet mapped
- mapped active
- degraded

That is enough to validate the behavior cleanly without overcommitting to premature retrieval/history-sync complexity.


## Draft official Shelley implementation seam map

Based on upstream inspection, the likely clean implementation path in official Shelley is not to add Stavrobot as a normal model provider. It is to add a conversation/runtime branch that sits above the ordinary provider layer.

Recommended seam map:

### 1. Conversation metadata layer

Responsibility:

- read/write per-conversation `conversation_options`
- determine whether a conversation is in normal mode or Stavrobot mode
- store the selected installer-managed `bridge_profile`
- store the mapped remote `conversation_id` and optional `last_message_id`

Why this layer matters:

- it is the durable source of per-conversation mode selection
- it lets one Shelley instance host both ordinary and Stavrobot-backed conversations side by side

### 2. Conversation send/runtime dispatch layer

Responsibility:

- when a user sends a turn, decide whether this conversation should:
  - go through Shelley's normal LLM/provider path
  - or go through the Stavrobot-mode path

Recommended behavior:

- if `mode != "stavrobot"`, preserve current Shelley behavior unchanged
- if `mode == "stavrobot"`, dispatch to a dedicated Stavrobot conversation runner that invokes `shelley-stavrobot-bridge.sh`

This is the most important seam because it avoids pretending Stavrobot is merely another direct model endpoint.

### 3. In-flight status / streaming/wait-state layer

Responsibility:

- expose the existing Shelley user-visible working state while a turn is being processed

Recommendation:

- reuse Shelley's existing `Agent Working...` behavior while Shelley is waiting for the Stavrobot bridge/remote response
- treat this as the natural wait-state for Stavrobot mode as well
- if Shelley later gains finer-grained mode-specific status text, the first useful extension would be something like:
  - `Agent Working... (Stavrobot)`
  - or a detail/status pane that says `Waiting for Stavrobot response`

Important note:

- the first Shelley-side spike does not need custom streaming semantics to benefit from the existing working indicator
- even if the bridge currently behaves more like request/response than true stream passthrough, the existing working state is still useful and should be leveraged

### 4. Message/content mapping layer

Responsibility:

- map returned Stavrobot payloads into Shelley's native message/content/display structures

This is the layer where the rich-output concern becomes real.

Recommended first version:

- accept plain response text cleanly
- preserve markdown as markdown-friendly content rather than flattening/escaping unnecessarily
- store returned IDs and optional metadata alongside Shelley's local message records

Recommended follow-on direction:

- support bridge-returned structured payloads that can map into Shelley's richer native content model
- support tool/event summaries or references in a way that Shelley can present legibly
- support screenshot/image/media references rather than collapsing everything to one flat text blob

### 5. Optional history/event reconciliation layer

Responsibility:

- pull remote Stavrobot history/events when Shelley needs to reconcile state, enrich display, or inspect tool traces

Recommended first version:

- keep this separate from the send-turn path
- allow future use of:
  - conversation history endpoint
  - events endpoint
- treat remote history/event sync as enrichment/reconciliation, not as a precondition for every ordinary user turn

## Recommended first Shelley-side code ownership shape

Conceptually, the implementation likely wants:

- conversation option parsing/validation near Shelley's conversation metadata handling
- a dedicated Stavrobot-mode dispatcher/runner near the conversation execution path
- bridge invocation isolated behind a small internal interface so Shelley is not tightly coupled to shell command details everywhere
- message/content mapping centralized rather than spread across UI handlers

In practical terms, that means the future Shelley patch should likely add something like:

- a Stavrobot mode detector/helper
- a Stavrobot turn executor
- a bridge result mapper
- optional remote history/event fetch helpers later

Not necessarily with those exact filenames, but that ownership split is the one to preserve.

## `Agent Working...` implication

Your observation is good.

Shelley's existing `Agent Working...` behavior should absolutely be reused for Stavrobot mode waiting states.

Recommended rule:

- once Shelley accepts a user turn and dispatches it through the Stavrobot runner, show the same existing in-flight working signal it already uses for ordinary agent/model processing
- clear that state only when Shelley has either:
  - received a successful bridge result and rendered it
  - or reached a terminal failure state for that turn

Why this is the right fit:

- it preserves a familiar user affordance
- it avoids inventing a second waiting UX too early
- it keeps Stavrobot mode feeling like a native conversation mode rather than a bolted-on side channel

A later refinement could add mode-aware detail text, but the existing working indicator is enough for the first implementation.

## Rich markdown/media/tool handling implication for the shell wrappers

Yes: this absolutely still needs to be accounted for later, and it should now be treated as a concrete future bridge requirement rather than just a note.

Current reality:

- the canonical bridge currently defaults to response-only output, which is correct for a minimal first integration surface
- but Shelley already has stronger native rendering and tool/media affordances than a plain-text bridge can express

So the future requirement should be explicit:

### Current minimal bridge role

Good for:

- basic request/response chat
- stable remote conversation continuation
- simple response text display

### Required bridge evolution later

The canonical bridge should remain the only Shelley-facing contract, but it will likely need a richer machine-readable mode that can return more than plain response text.

That likely means preserving support for outputs such as:

- markdown response text without destructive flattening
- conversation/message IDs
- tool/event references or summaries
- image/screenshot/media references when Stavrobot can provide them
- possibly structured content blocks if Shelley can map them natively

### Practical implication for wrapper design

The lower-level wrappers should remain implementation details, but the canonical bridge should be allowed to evolve upward into structured output.

So future bridge work should likely add or refine capabilities such as:

- a stable JSON output mode for Shelley consumption
- richer extraction or pass-through of structured response fields
- optional history/event fetch helpers exposed through the bridge contract rather than forcing Shelley to call lower-level wrappers directly

### Important discipline

- do not force Shelley to integrate separately with `client-stavrobot.sh` and `shelley-stavrobot-session.sh`
- evolve `shelley-stavrobot-bridge.sh` itself when richer output is needed
- keep plain response-text mode as the conservative default, but preserve a structured mode for Shelley-native rich rendering later

That is how we make sure the earlier observation about markdown/media/tool fidelity actually turns into implementation work instead of remaining just a warning in the docs.
