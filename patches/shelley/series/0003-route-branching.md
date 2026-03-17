# Patch 0003: route branching only

## Goal

Keep handler changes thin.

Handlers should decide whether a request stays on ordinary Shelley flow or dispatches into the Stavrobot runtime path.

They should not own the Stavrobot runtime machinery.

## Upstream file owned

- `server/handlers.go`

## Managed target behavior

### `handleNewConversation`

Should:

- accept `conversation_options.type = "stavrobot"`
- validate that Stavrobot options are enabled and include a non-empty `bridge_profile`
- create the Shelley conversation normally
- branch into the focused Stavrobot runtime path when the new conversation is in Stavrobot mode
- otherwise keep ordinary Shelley behavior unchanged

### `handleChatConversation`

Should:

- detect existing Stavrobot-mode conversations
- reject unsupported queue mode for S1 if that limitation remains
- dispatch into the focused Stavrobot runtime path
- otherwise keep ordinary Shelley behavior unchanged

## What must not remain in handlers

Do not keep these details in `server/handlers.go`:

- profile-state file loading/parsing
- bridge argv assembly rules
- bridge subprocess execution details
- bridge JSON output parsing
- full message-recording orchestration details beyond calling the runtime entrypoint

## Expected runtime call boundary

Handlers should call something conceptually like:

- `ProcessStavrobotConversationTurn(...)`

and translate success/failure into the appropriate HTTP response.

## Disposable source mapping

Primary source sections in `../s1-stavrobot-mode-disposable-shape.patch`:

- `handleNewConversation` additions
- `handleChatConversation` additions

The disposable helper functions at the bottom of `server/handlers.go` are *not* the target shape for this patch. They belong in patch 4 after cleanup.

## Definition of done for this patch

- route handlers branch above the normal provider/model path
- ordinary Shelley mode still behaves exactly as upstream when Stavrobot mode is off
- handlers are thinner than the disposable spike
- no hardcoded bridge/profile/config/base-URL logic remains in handlers
