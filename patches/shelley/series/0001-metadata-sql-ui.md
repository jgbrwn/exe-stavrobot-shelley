# Patch 0001: metadata, SQL, and UI type support

## Goal

Carry forward the parts of the disposable spike that already looked close to final managed shape.

## Upstream files owned

- `db/db.go`
- `db/query/conversations.sql`
- `db/generated/conversations.sql.go`
- `ui/src/types.ts`

## Disposable shape to preserve mostly as-is

From the captured disposable patch, these are already close to correct:

- `ConversationOptions` gains `Stavrobot *StavrobotOptions`
- `StavrobotOptions` includes:
  - `enabled`
  - `conversation_id`
  - `last_message_id`
  - `bridge_profile`
- `ConversationOptions.IsStavrobot()` exists
- SQL query `UpdateConversationOptions` exists
- frontend request typing understands Stavrobot-capable `conversation_options`

## Managed cleanup expected here

Minimal.

This patch should remain intentionally boring.

It should not know about:

- profile-state file paths
- bridge execution
- runtime branching details

## Notes for final apply-ready patch

- regenerate `db/generated/conversations.sql.go` from SQL source rather than hand-editing if practical
- keep conversation metadata small and secret-free
- keep `bridge_profile` as a name only

## Disposable source mapping

Primary source sections in `../s1-stavrobot-mode-disposable-shape.patch`:

- `db/db.go`
- `db/query/conversations.sql`
- `db/generated/conversations.sql.go`
- `ui/src/types.ts`

## Definition of done for this patch

- Shelley data model understands Stavrobot conversation metadata
- SQL layer can persist updated `conversation_options`
- frontend typing accepts Stavrobot conversation options
- no installer-managed path assumptions exist in this patch
