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
