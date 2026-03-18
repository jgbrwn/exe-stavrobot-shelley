# Shelley S4 recall validation template

## Purpose

Turn the existing S4 roadmap guidance into an execution-ready validation artifact so future sessions can gather evidence about Stavrobot cross-conversation recall in a consistent way.

This document is a template and procedure, not a claim that recall has already been validated.

## Why this exists

The project already has a clear architectural recommendation:

- do not assume Shelley needs its own retrieval layer before testing Stavrobot-native recall more deeply

What was still missing was an operator/research-ready artifact for actually collecting that evidence.

This file fills that gap.

## Validation question

Primary question:

- Does Stavrobot already handle realistic cross-conversation recall well enough that Shelley can defer building explicit retrieval orchestration?

Possible outcomes:

- **S4A:** Stavrobot-native recall is good enough for now
- **S4B:** Shelley should add explicit retrieval/reconciliation UX later

## Preconditions

Before running this validation:

- a live Stavrobot instance is reachable
- the local Shelley/Stavrobot path under test is known
- the bridge/profile/config under test are recorded
- the model/provider in use are recorded
- test conversations can be created without contaminating important production history

Recommended metadata to record up front:

- date/time
- Shelley build/commit under test
- Stavrobot repo/build/commit under test when known
- active provider/model
- bridge profile used
- base URL used
- whether testing was done through Shelley UI, bridge helper, or lower-level client helper

## Minimum test matrix

Run at least these four scenario classes.

### 1. Single long-lived conversation recall

Goal:

- measure whether ordinary active-thread continuity is already strong enough for many practical workflows

Procedure:

1. create one Stavrobot conversation
2. perform several clearly separated tasks within that same conversation
3. later ask recall-style questions about earlier work in the same conversation

Examples:

- earlier we discussed plugin configuration
- later ask about that prior plugin decision

### 2. Multiple separate conversation recall

Goal:

- measure whether Stavrobot can recall work that happened outside the active conversation

Procedure:

1. create at least two or three distinct conversations
2. keep their topics clearly separated
3. ask from one conversation about work done in another conversation

Examples:

- conversation A: plugin install choices
- conversation B: OpenRouter model/provider setup
- conversation C: Shelley managed rebuild work

### 3. Time-separated work recall

Goal:

- simulate realistic "we did this before" prompts rather than only immediate turn-to-turn recall

Procedure:

1. separate topic setup into distinct sessions when practical
2. ask later with phrasing that implies prior work over time
3. note whether quality drops when time separation is implied

### 4. Tool/event-heavy history recall

Goal:

- determine whether recall remains useful when the earlier work depended on tool usage, not only plain prose

Procedure:

1. create at least one conversation involving tools/actions
2. later ask about the earlier tool-driven result or decision
3. note whether Stavrobot recalls useful outcome details versus only generic text context

## Prompt probe set

Use a mix of generic and repo-specific prompts.

### Generic probes

- `Remember when we worked on X a while ago?`
- `What did we decide about Y last week?`
- `Did we already solve the problem with Z in another conversation?`
- `Find the earlier conversation where we discussed A.`
- `What was the config change we made before?`

### Repo-specific probes for this project

- `What did we decide about OpenRouter provider handling earlier?`
- `Did we already add a managed Shelley status warning for dirty rebuilds?`
- `What helper did we add for Stavrobot backend model control?`
- `Did we already decide whether cross-conversation recall should be explicit or automatic?`
- `What was the earlier recommendation for richer structured bridge output?`

## Observation rubric

For each probe, capture all of the following.

### A. Accuracy

Classify as one of:

- `correct`
- `partially_correct`
- `incorrect`
- `claims_not_to_know`
- `unclear`

### B. Scope behavior

Classify what it appears to have relied on:

- `active_conversation_only`
- `appears_cross_conversation`
- `unclear_scope`

### C. User experience quality

Classify as one of:

- `acceptable`
- `borderline`
- `confusing`

### D. Notes to capture

Always note:

- whether the answer changed substantially based on prompt phrasing
- whether the answer hallucinated details from the wrong conversation
- whether same-thread continuity was much stronger than cross-thread recall
- whether tool/event-heavy history appeared especially weak

## Suggested result table

Use a simple table like this for each run.

| scenario | probe | accuracy | scope_behavior | ux_quality | notes |
|---|---|---|---|---|---|
| single-thread | What did we decide about plugin config earlier? | correct | active_conversation_only | acceptable | same-thread continuity looked strong |
| cross-thread | Did we already solve model-control helper wiring in another conversation? | incorrect | active_conversation_only | confusing | answered only from current thread |

## Fork decision guide

Choose **S4A** if most realistic probes show:

- correct or mostly correct answers
- acceptable UX
- only occasional failures
- no strong product pressure for explicit retrieval UX yet

Choose **S4B** if testing repeatedly shows:

- weak or inconsistent cross-thread recall
- confusion between conversations
- materially better results when humans manually retrieve prior conversation history
- enough user confusion that explicit retrieval would clearly help

## Recommended output note format

When someone runs this validation, record the result in a short companion note using this structure:

### Validation metadata

- date:
- operator:
- Shelley build/commit:
- Stavrobot build/commit:
- provider/model:
- profile/base URL:
- path used: UI / bridge / client

### Scenario summary

- scenario 1 result:
- scenario 2 result:
- scenario 3 result:
- scenario 4 result:

### Table of probe observations

- include the result table

### Decision

- provisional outcome: `S4A` or `S4B`
- confidence: `low` / `medium` / `high`
- rationale:

### Follow-up recommendation

- if `S4A`: what minimal monitoring or explanatory UX, if any, is still useful?
- if `S4B`: what is the minimum explicit retrieval/reconciliation feature worth building first?

## Guardrails

- do not declare recall solved from only same-thread continuity tests
- do not declare recall failed from one badly phrased probe
- do not assume semantic/global search exists unless it was truly provided by the system under test
- do not present explicit retrieval as "native memory" if the user would actually be triggering a separate search/reconciliation step

## Relationship to other docs

Use this template alongside:

- `docs/SHELLEY_STAVROBOT_MVP.md`
- `docs/SHELLEY_STRATEGIC_GAP_AUDIT.md`
- `docs/STAVROBOT_API_NOTES.md`

## Status

Current status remains:

- cross-conversation recall is unresolved pending validation
- this template exists so the next validation pass can produce evidence rather than more speculation
