# Task Reviews

Reviewers create one file per task and reviewer:

```text
reviews/<task-id>--<reviewer-id>.md
```

Only the named reviewer edits that file. Use
[`../templates/REVIEW.md`](../templates/REVIEW.md). The implementation owner
responds through its mailbox or a follow-up task; it does not rewrite review
findings.

Review is read-only unless the board assigns a separate fix task with explicit
path claims. A passing test suite does not replace architecture, compatibility,
security, tenancy, or UX review.
