# Decision records

Each record states one architectural decision, its context, and its
consequences. The status line at the top of a record says where the decision
stands.

## Statuses

- **Proposed** — written down, not yet agreed by the owner. A decision that is
  not yet built stays Proposed until the owner approves it.
- **Accepted** — the owner agreed the decision. It is usually also built.
- **Superseded by ADR NNNN** — a later record replaced it; the later record
  carries the current rule.
- **Withdrawn** — what the record describes no longer exists and nothing
  replaced it; the line says why.

## Who may change a status

The owner decides. An agent may move a record to Accepted only in, or after,
the PR that implements the decision, once that PR merges with the owner's
approval, and the PR must say so. Otherwise the record stays Proposed.

## Records

| Record | Status |
| --- | --- |
| [0001 Mix umbrella application topology](./0001-mix-umbrella-topology.md) | Superseded by ADR 0003 |
| [0002 Compatible schema baselines and adoption](./0002-compatible-schema-baselines.md) | Accepted |
| [0003 Physical deep-module packages](./0003-physical-deep-module-packages.md) | Accepted |
| [0004 Descriptor-owned module contribution providers](./0004-module-contribution-contract.md) | Accepted |
| [0005 Laravel framework residue and the Bilimbi job runtime](./0005-laravel-framework-tables-and-job-runtime.md) | Accepted |
| [0006 Module-owned web adapters and route discovery](./0006-module-owned-web-adapters.md) | Accepted |
| [0007 Contained Core User Administration integration read](./0007-core-user-administration-integration-read.md) | Accepted |
| [0008 Core Employee Type tenancy and compatibility migration](./0008-core-employee-type-tenancy-and-compatibility.md) | Accepted |
| [0009 Dashboard widget catalogue as a contribution consumer](./0009-dashboard-contribution-consumer.md) | Accepted |
| [0011 Principal directory seam and its query boundary](./0011-principal-directory-seam.md) | Accepted |
| [0012 Schedule recurrence as a contribution consumer](./0012-schedule-contribution-consumer.md) | Accepted |
| [0013 Repo-level audit mutation capture](./0013-repo-level-audit-mutation-capture.md) | Accepted |
| [0014 The principal directory names referenced identities](./0014-directory-names-referenced-identities.md) | Accepted |
| [0015 Review-gate independence by marker identity](./0015-review-gate-independence-by-marker-identity.md) | Withdrawn |
| [0016 The authenticated actor travels on the tenant scope](./0016-authenticated-actor-on-scope.md) | Accepted |
| [0017 Routine system work runs as a named system principal](./0017-named-system-principals.md) | Accepted |
| [0018 Workflow status definitions and owner adapters](./0018-workflow-status-contribution-consumer.md) | Accepted |
| [0019 Grid table catalog as a contribution consumer](./0019-grid-contribution-consumer.md) | Accepted |
| [0020 Per-owner migration ledger and absent optional structure at adoption](./0020-per-owner-ledger-and-absent-optional-structure.md) | Proposed |
