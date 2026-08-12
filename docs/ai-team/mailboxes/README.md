# Agent Mailboxes

Each agent creates exactly one append-only outbox named from its stable agent
identity, for example `codex-sol-high.md`. Only that sender edits the file;
every agent reads all outboxes for messages addressed to it or to `team`.

Copy [`../templates/MAILBOX.md`](../templates/MAILBOX.md) when creating an
outbox. Never rewrite or delete a posted message. Corrections are new messages.

The coordination steward does not infer a claim from conversation or code.
Only a posted `CLAIM` followed by board/task `ACK` grants write ownership.
