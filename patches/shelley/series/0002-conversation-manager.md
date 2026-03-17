# Patch 0002: conversation manager support

## Goal

Keep the validated conversation-manager helpers that already looked close to the correct managed shape.

## Upstream file owned

- `server/convo.go`

## Disposable shape to preserve mostly as-is

The captured disposable patch already introduced the right kinds of helpers:

- `IsStavrobotMode()`
- `StavrobotOptions()`
- `UpdateStavrobotMapping()`

## Managed cleanup expected here

Minimal.

But keep the responsibility boundary narrow:

- conversation manager exposes/accesses per-conversation Stavrobot state
- conversation manager persists updated remote mapping
- conversation manager does not resolve installer-managed bridge profiles
- conversation manager does not execute the bridge

## Important behavior

`UpdateStavrobotMapping()` should remain the Shelley-side persistence hook used after a successful Stavrobot turn.

It should be callable from the focused runtime unit without forcing handler-local knowledge of the DB update details.

## Disposable source mapping

Primary source section in `../s1-stavrobot-mode-disposable-shape.patch`:

- `server/convo.go`

## Definition of done for this patch

- handler/runtime layer can ask whether the conversation is in Stavrobot mode
- handler/runtime layer can fetch current Stavrobot options safely
- runtime layer can persist updated remote `conversation_id` / `last_message_id`
- no installer-managed path assumptions exist in this patch
