# ADR 0022: Workflow transition events and maintenance

**Document Type:** Architecture Decision Record
**Status:** Proposed
**Agents:** claude/opus-5.5
**Scope:** How Base Workflow delivers committed status transitions to other modules, and how its every-minute process and outbox maintenance runs
**Last Updated:** 2026-10-11

> This record amends one consequence of
> [ADR 0018](./0018-workflow-status-contribution-consumer.md): external
> dispatch is no longer a later slice, and retained outbox rows are
> delivered once their subject is adopted. The module contract is in
> `apps/base/workflow/docs/README.md` under "Transition events" and
> "Maintenance".

## Context

Belimbing writes one `base_workflow_transition_outbox` row in every
transition's transaction, delivers it after commit by firing a
`TransitionCompleted` event, and retries due rows from the every-minute
`blb:workflow:reconcile` command, which also repairs process leases and
timers. Its notification listener and every module that reacts to a status
change depend on that path. ADR 0018 adopted the outbox table and its rows
but left delivery and the reconcile sweep unported, so a Bilimbi owner had no
safe place for an effect outside the database: a guard or action runs inside
the transaction and cannot reach the outside, and code that runs after
`transition/4` returns is lost when its process dies.

## Decision

A module reacts to transitions through a `transition_listeners` entry in its
`:workflow` contribution: a stable key, a descriptor-owned module that
implements `Bilimbi.Base.Workflow.TransitionListener`, and the registered
subjects it listens to. A listener may name another owner's subject, because
a committed transition is a published fact; it can never refuse or alter
one.

Each transition writes Belimbing's outbox row, with Belimbing's event key and
payload shape, and inserts a Base Queue job for the immediate delivery
attempt, both in the transition's own transaction. A rolled-back transition
leaves neither, and no in-process after-commit hook is needed. The row, not
the job, is the retry authority: a short database lease guards each attempt,
a failure of any listener defers the whole event with Belimbing's exponential
backoff and keeps the reason, and the next attempt calls every listener
again. Delivery is at least once and listeners are idempotent on the event
key.

Listeners run under the subject tenant's system scope. Delivery takes the
tenant and subject from the proven subject binding, never from the row, so a
retained Belimbing row is delivered under the right tenant once its subject
is adopted and is deferred until then.

Base Workflow contributes Belimbing's reconcile as a Base Schedule definition
that runs every minute once an operator reviews it, and as
`mix bilimbi.workflow.reconcile`. A pass settles every running tenant run of
every live tenant on its saved graph under that tenant's system scope,
without asking the owner's `:reconcile` policy, then delivers due events.
This is Base's own lease and timer hygiene: it executes no owner code beyond
the subject lock, and skips, logging it, a run whose definition, subject or tenant it
cannot prove or whose subject lock raises; delivery runs even if the sweep
fails.

## Consequences

- An effect outside the database (a notification, a call to another
  service, a follow-up workflow) is written as a listener. Calling it from a
  guard, an action or the caller of `transition/4` is the copy this
  replaced.
- The listener event is a plain map; Belimbing's rehydrated Eloquent models
  and actor object have no equivalent. A listener that needs current subject
  state reads it through its owner's API.
- Maintenance and delivery writes are audited with the guest default, because
  nobody signed in and no system principal is named. A listener that must be
  attributed to a principal enqueues its own work as that principal.
- Until the schedule definition is reviewed, deferred events and expired
  leases wait for the next manual pass; the immediate attempt still runs.
- No schema changes: the outbox, run and work tables are ADR 0018's
  compatible baseline.
