# ADR 0017: routine system work runs as a named system principal

**Document Type:** Architecture Decision Record
**Status:** Accepted
**Agents:** claude-opus-5.5
**Scope:** How a background job that nobody signed in for gets an identity,
and how that identity gets, and loses, authority
**Last Updated:** 2026-09-27

## Context

ADR 0016 put a sealed actor on every scope: a user, attached only by the
authentication edge or by a job enqueued for that user, or the system, which
holds no authority. That left routine system work with two choices, and both
are wrong.

- Run it as the anonymous system actor. Base Authz denies it every
  capability, so a scheduled import can do nothing that checks one.
- Run it for a user through `Queue.enqueue_for/3`. The import then borrows a
  person's account and authority. It stops when that person leaves, and the
  audit trail says a person did work that a routine did.

The first consumer made the gap concrete. Factory accepts a system scope for
an import only if its principal holds the import capability explicitly. A
scheduled import from a coating line's source system should run as its own
identity, such as `coating.line_import`, but Bilimbi had no way to name that
identity or grant it anything.

## Decision

1. **A module declares the system principals its jobs run as.** A new
   contribution key, `:system_principals`, sits beside those of ADR 0004,
   0009, 0011, 0012, and 0016. Each entry is
   `%{name:, description:, capabilities:}`. `capabilities` lists what the
   principal may ever be granted. Base Tenancy owns the validator: a name is
   dot-separated lowercase segments, such as `coating.line_import`, and belongs to
   exactly one installed module. A duplicate or malformed declaration stops
   the contribution snapshot, and with it boot.

   The declaration is a contribution, not a new descriptor field. The
   descriptor is Mix-time graph data. Runtime declarations, such as
   capabilities and menus, already travel as contributions from the provider
   the descriptor names, and are validated from the same composition graph
   when the snapshot is built.

2. **The principal is a system actor with a name and a company.** A named
   system actor carries `system_principal` and the `company_id` its job works
   in, sealed to the tenant exactly as in ADR 0016. It has no `user_id`.
   `Authentication.sign_in/4` refuses a scope that already names a principal,
   so a principal can never become a user or be impersonated. It cannot be
   delegated with `enqueue_for/3`. `Authz.scope_actor/1` returns no principal
   for it, so it can never be recorded as an approver. A struct literal, a
   struct update, a rename, a company change, or a move to another tenant
   fails `Scope.actor/1`.

3. **Only Base Queue attaches a principal, and only to its declaring
   module's worker.** A worker declares its principal as a compile-time fact:
   `use Bilimbi.Base.Queue.Worker, system_principal: "coating.line_import"`.
   `Queue.enqueue_as_system(scope, company_id, worker, args)` is the one way
   to enqueue it. Before it enqueues, Queue checks three things: the name is
   declared, the worker module belongs to the OTP application that declared
   it, and the company ID is positive. Base Tenancy then signs the tenant,
   the name, and the company into job metadata under its own salt. Only the
   enqueuing scope's tenant is used, never its actor.

   When the job runs, `Queue.Worker` is the one caller of
   `Authentication.resume_system/2`. That call re-verifies the token and the
   tenant, and checks that the name is still declared. The worker then checks
   that the name is the one this worker declared, and that the worker still
   belongs to the declaring module. A principal's worker is refused by
   `enqueue/2` and `enqueue_for/3`. A unique worker is refused, as in ADR
   0016. A token that fails any check cancels the job before it runs.

4. **Grants are explicit, per company, and only of declared capabilities.**
   Base Authz stores them in the Bilimbi-only
   `base_authz_system_principal_capabilities` table: one row per company,
   principal, and capability. They cannot share
   `base_authz_principal_capabilities`, whose principals are Belimbing's
   numeric user and agent IDs. There are no deny rows, no roles, and no
   `grant_all`. Revocation deletes the row.

   `Authz.can(scope, capability)` on a principal's scope allows only when all
   of the following hold:
   - the principal is still declared;
   - its company is in the scope's tenant;
   - the capability is registered and still declared for that principal;
   - a grant row exists for that company.

   The resource tenant and company checks apply as they do for users.
   Anything else is denied. A grant that a module stops declaring becomes
   inert, and so does a row written around the API. The decision log records
   `actor_type` `"system"`, `actor_id` `0`, and the principal's name in its
   context.

5. **Granting is a person's act, or an operator's at the shell.**
   `Authz.grant_system_capability/4`, `revoke_system_capability/4`, and
   `list_system_capabilities/2` require the scope's sealed user to hold
   `admin.authz.system-principal.grant`, `.revoke`, or `.list`. A system
   scope is refused, named or not, so a principal can never grant itself.
   `mix bilimbi.authz.system_principal` is the operator's path. Like the
   database console, whoever runs it has a shell on the server and no
   sign-in, so it records `console`.

   Every grant and revocation commits together with an
   `authz.system_principal.granted` or `.revoked` audit action that names who
   made it, and any impersonating operator. The captured row write is also
   recorded.

6. **Audit names the principal.** A principal's job sets
   `Bilimbi.Base.Audit.Context` to `actor_type` `"system"`, `actor_id` `0`,
   and `system_principal`, plus the job's tenant and company. It clears the
   context afterwards. `"system"` joins the audit actor types. The principal's
   name goes in a Bilimbi-only `system_principal` column on
   `base_audit_mutations` and `base_audit_actions`, declared as an optional
   group in the Base Audit schema contract, as `impersonator_id` was. A row
   with a principal must be a `"system"` row, and a `"system"` row must name
   one.

## Consequences

- Base Queue now depends on Base Audit, and Base Authz depends on Base Audit.
- A deployment grants nothing to a principal until an administrator does.
  Installing a module that declares one changes no decision.
- Uninstalling the declaring module, or dropping a capability from its
  declaration, disables the matching grants without deleting them. Queued
  jobs for a principal nobody declares any more are cancelled as
  `:system_principal_refused`.
- A job runs for one company. Work across several companies enqueues one
  job for each.
- The anonymous system actor keeps its meaning: seeds, mix tasks, and plain
  `enqueue/2` jobs run as nobody and hold no authority.
- Factory's import check and the first scheduled import job are the first
  consumers. Each lives in its own repository and is wired in its own change.
- There is no administration screen yet. Grants are made through the API or
  the mix task.
