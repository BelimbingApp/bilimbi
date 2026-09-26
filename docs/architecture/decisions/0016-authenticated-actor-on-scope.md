# ADR 0016: the authenticated actor travels on the tenant scope

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Agents:** claude-opus-5.5
**Scope:** How module code learns who performed an operation, and why it
cannot be told
**Last Updated:** 2026-09-27

## Context

`Bilimbi.Base.Tenancy.Scope` proved which tenant a unit of work belonged to
and nothing else; its moduledoc promised an actor field once authentication
landed. The Web host already knew the signed-in user, but only in its own
`current_scope` map. A module API that needed the person performing an
operation had to take it as an argument, and anything that is an argument is
whatever the caller says.

The first consumer made the gap concrete. Factory's material-hold override
records an approver and checks the approver's Authz capability, but both use an
approver its caller names. A screen or import that exposes the override could
approve as anyone. Workflow approvals, a later port, need the same guarantee.

## Decision

1. **Every scope carries an actor.** `Scope.actor/1` returns a
   `Bilimbi.Base.Tenancy.Actor`: `:user` (with `user_id`, `company_id`, and
   `impersonator_id` under impersonation) or `:system`. `Tenancy.scope/1` and
   `Scope.for_tenant/1` build the system actor, so every existing tenant-only
   call site keeps working and is correctly labeled as nobody. The system actor
   carries no authority.

2. **Only the authentication edge attaches a user.**
   `Bilimbi.Base.Tenancy.Authentication.sign_in/4` has one caller,
   `BilimbiWeb.UserAuth`, which calls it only after proving the durable
   session, the user, the company, and the tenant. That happens once per HTTP
   request and once per LiveView mount, so `@current_scope.scope` names the
   signed-in user everywhere. A scope's actor is set once. Signing in a scope
   that already names a user raises.

3. **The actor is sealed to its tenant.** An HMAC over the actor and tenant
   ID, keyed by `:bilimbi_base_tenancy, :actor_secret`, is verified by
   `Scope.actor/1`. A struct literal, a struct update, or an actor moved onto
   another tenant's scope raises `ForgedActorError`. Production derives the
   secret from `SECRET_KEY_BASE`, so no new deployment variable is needed, and
   scopes verify across clustered nodes.

4. **The fence is tested.** Elixir cannot restrict a public function to one
   caller. `apps/web/test/bilimbi_web/scope_actor_boundary_test.exs` reads the
   BEAM import table of every loaded Bilimbi module, including mounted Domains
   and Extensions, and fails for any caller of `sign_in`, `resume`, or the seal
   outside its allowlist. Reading compiled calls rather than source means
   aliases and macro expansion cannot hide a caller.

5. **Jobs act for a user through Base Queue.** `Queue.enqueue_for/3` stores a
   token signed from the enqueuing scope in job metadata, not in the
   caller-shaped arguments. `Queue.Worker` is the one caller of
   `Authentication.resume/2`, which verifies the token (one-week lifetime) and
   re-proves the tenant. The worker then receives the user's scope in
   `execution.scope`. A token that fails verification cancels the job before
   the worker runs.

6. **Authz asks the scope.** `Authz.can/4` and `authorize!/4` accept a scope
   and judge its actor. A system scope is denied as
   `:denied_no_authenticated_actor`. `Authz.scope_actor/1` returns the
   principal. `Authz.actor/5` remains for evaluating somebody else, such as an
   administration preview. It is never the way to ask about the performer.

## Consequences

- Domain APIs that record a performer drop the performer argument and read
  `Scope.actor/1`. Factory's override is the first follow-up and lives in its
  own repository.
- An operation that must be a person's own act decides what impersonation
  means for it: record `impersonator_id` alongside the actor, or refuse.
- Base Queue now depends on Base Tenancy.
- A delegated job's capability checks run against live grants when it runs.
  Base cannot see Core User, so a worker that must also re-prove the account
  (for example, that it is still active) does so through Core User's API.
- Rotating `SECRET_KEY_BASE` signs everyone out, as before, and now also
  cancels queued jobs that act for a user.
- Captured audit rows from a delegated job still use the guest default unless
  the worker sets `Bilimbi.Base.Audit.Context`. Wiring that from
  `execution.scope` is a separate change.
