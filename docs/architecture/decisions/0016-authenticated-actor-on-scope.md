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

4. **The seal is the enforcement.** Elixir cannot restrict a public function
   to one caller, and a scan of compiled calls cannot either: `apply/3` or a
   module held in a variable hides a caller from it. So no test claims to
   fence `Authentication`. What holds is the seal: an actor that
   `Authentication` did not issue fails `Scope.actor/1`, which the tenancy
   seal tests prove by forging one every way data can. Calling `sign_in/4`
   from module code is asserting an identity nobody proved; review rejects
   it, and adding a caller is a change to this ADR.

5. **Jobs act for a user through Base Queue, and re-prove the user.**
   `Queue.enqueue_for/3` stores a token signed from the enqueuing scope in job
   metadata, not in the caller-shaped arguments. `Queue.Worker` is the one
   caller of `Authentication.resume/2`, which verifies the token (one-week
   lifetime), re-proves the tenant, and then asks the installed
   `Bilimbi.Base.Tenancy.ActorVerifier` to re-prove the user. The worker then
   receives the user's scope in `execution.scope`. A token that fails
   verification cancels the job as `:delegated_actor_unavailable`; a user the
   verifier refuses cancels it as `:delegated_actor_refused`; no installed
   verifier cancels it as `:no_actor_verifier`. The worker never runs.

   Base cannot read accounts or sessions, so Tenancy owns the behaviour and a
   new contribution key, `:actor_verifier`, beside those of ADR 0004, 0009,
   0011, and 0012. Its validator accepts at most one verifier. Core User
   contributes `Bilimbi.Core.User.ActorVerifier`: the user must still exist in
   the actor's company, as at the request edge, and a job queued under
   impersonation also needs the borrowed durable session to still belong to
   the impersonated account. The actor therefore carries that session's ID
   (`impersonation_session_id`) under impersonation. A user's own sign-out
   does not cancel work they queued.

   `enqueue_for/3` refuses workers that declare `unique_period`. Oban's
   uniqueness compares arguments, not metadata, so a duplicate would be
   absorbed by a job carrying another actor, or none.

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
- A delegated job's capability checks run against live grants when it runs,
  and its user is re-proven through the `:actor_verifier` contribution before
  that.
- A deployment without Core User has no verifier, so its delegated jobs are
  refused rather than trusted.
- Rotating `SECRET_KEY_BASE` signs everyone out, as before, and now also
  cancels queued jobs that act for a user.
- Captured audit rows from a delegated job still use the guest default unless
  the worker sets `Bilimbi.Base.Audit.Context`. Wiring that from
  `execution.scope` is a separate change.
