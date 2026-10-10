# ADR 0021: External agents act for a person through granted connections and self-registered API operations

**Document Type:** Architecture Decision Record
**Status:** Proposed
**Agents:** claude-code/opus-5.5
**Scope:** How an AI agent running outside Bilimbi is connected to a person,
what it may do, how it finds and calls operations any installed module
registers, and how its work is recorded
**Last Updated:** 2026-10-11

> This record adds a second caller to the authentication edge of
> [ADR 0016](./0016-authenticated-actor-on-scope.md) and a peer consumer to
> the contribution contract of [ADR 0004](./0004-module-contribution-contract.md).
> It keeps AI out of Bilimbi: no model runs inside the platform.

## Context

People want agents they already use, such as coding agents and chat apps, to
look things up and fill in records in Bilimbi. The owner decided that Bilimbi
itself stays free of AI, that agents come in through an API that runs the
same operations and checks as the screens, that a connection belongs to a
person and never exceeds that person's permissions, that it is read-only by
default with risky writes drafted for a person's approval, and that audit
names the agent, the person, the channel and the run.

Four facts shaped the decision.

- The authentication edge seals one actor onto each scope (ADR 0016), and
  only the browser edge attaches a person. Nothing accepts a token.
- Capability checks are split. A route declares the capability that opens
  a page, an event re-asks for an operation's capability, and some facades
  check nothing themselves: `Company.update_company/3` relies on its page.
  An API that only called facades would skip checks the screens make.
- Belimbing's word "agent" already means an employee of type agent, a
  digital worker, in audit actor types and Authz principals. Its rule that
  such an agent may never exceed its supervisor's permissions is the right
  invariant, but Bilimbi's evaluator does not enforce it.
- Most operations agents need will come from Domains and Extensions that
  are mounted per installation. Per-module API code would multiply, and a
  fixed list in an agent's instructions would always be stale.

## Decision

1. **A connection is an OAuth grant owned by one person.** Bilimbi is its
   own authorization server. A connection binds a person, the company they
   approved it in, and that company's tenant. It carries a level, `read`,
   `draft` or `write`, an optional area ceiling of capability keys, an
   end date, and the agent ID shown at approval. Core Agent Access
   (`core/agent_access`) owns connections and their tokens.
   - The primary way to connect is the device authorization grant (RFC 8628):
     the agent shows a code, and the person approves in Bilimbi on a page
     that names the stated agent ID, the level and the areas.
   - Authorization code with PKCE `S256` serves clients that can open a
     browser on a loopback address (RFC 8252) and operator-registered front
     ends.
   - Access tokens are opaque, last one hour and are stored only as hashes.
     Refresh tokens rotate, and replaying a rotated one revokes the
     connection.
   - There is no shared or service-account token. A shared front end
     obtains a grant per user.
   - A connection cannot be approved or used under impersonation.

2. **The bearer edge is the second caller of the authentication seam.**
   `BilimbiWeb.AgentAuth` proves the token, the connection, the company,
   the tenant and the person, with the browser edge's proof, then calls
   `Authentication.sign_in/4` with an `:agent` facet. The person is the
   actor (`type: :user`). The sealed facet names the connection, the agent
   ID stated on that request, the level and the ceiling. Domain code reads
   it only through `Scope.actor/1`. `delegate/1` refuses a facet scope.

3. **Authz bounds every agent facet.** For a facet scope, `Authz.can/4`
   decides for the person against live grants first, then denies:
   - a capability outside the ceiling (`:denied_agent_ceiling`);
   - a non-read verb unless the level is `write` (`:denied_agent_level`);
     the read verbs are `view`, `list` and `search`, and an unknown verb is
     a write;
   - every platform capability (`:denied_agent_platform`);
   - every access-control capability: role, grant, field-restriction and
     system-principal administration, impersonation, settings management,
     and agent-connection management.

   `scope_actor/1` carries the facet. `agent_reach/1` lists what a facet
   may propose. Workflow human actions refuse a facet, so an agent never
   approves anything.

4. **Audit names the person and the agent.** A facet's rows keep
   `actor_type "user"` and the person's `actor_id`. Four Bilimbi-only
   columns on `base_audit_mutations` and `base_audit_actions` record
   `agent_grant_id`, `declared_agent`, `channel` and `agent_run`, declared
   as an optional group in the Base Audit schema contract as
   `impersonator_id` and `system_principal` were. They appear only on
   `"user"` rows. The dispatcher records one audit action per API call,
   reads included. The `"agent"` actor type keeps its Belimbing meaning.

5. **Modules register operations; Base exposes them.** `:agent_api` is a
   peer consumer validated by `Bilimbi.Base.AgentApi.ContributionValidator`.
   - An entry declares a key, a title, a summary, keywords, `kind`
     (`:read` or `:write`), the capability the matching screen asks for,
     the write `approval` (`:level` or `:required`), an input schema, and a
     handler that implements `Bilimbi.Base.AgentApi.Operation`, belongs to
     the declaring OTP application, and calls its own facade with the scope
     it receives.
   - Modules may also contribute short guides.
   - A module that is not installed contributes nothing.
   - No module adds API routes. The host serves `/api/v1` and `/oauth`.

6. **Calls check what the screens check, and never more widely.** The
   dispatcher runs these steps in order:
   - validate the input's shape;
   - ask `Authz.can(scope, capability)`, the same key the screen's route or
     event asks;
   - decide whether a write runs or becomes a draft;
   - call the handler, so the facade's changesets, field restrictions and
     internal checks apply unchanged.

   A connection can only narrow what the person may do.

7. **Discovery is one search.** `search/3` ranks the operations and guides
   within the facet's reach by the words given, deterministically and
   without a model. `describe/2` returns one operation's schemas and
   guides. The Bilimbi skill teaches search, then describe, then call, and
   lists no operations.

8. **Risky writes are drafts approved by a person through Workflow.** A
   write runs at once only for a `write`-level connection and an operation
   with `approval: :level`. Otherwise it becomes a write request, a
   Workflow subject owned by Base Agent API. Its approve human action
   requires `base.agent-draft.approve`. It re-checks the operation's
   capability for the approver, refuses a record changed since the draft,
   and runs the operation with the approver's scope, all in the gate's
   transaction.

9. **The client is a skill, not a protocol server.** Bilimbi serves one
   generic skill with a small helper that signs in, keeps tokens out of the
   conversation, and sends the agent ID (`harness/model-ver-effort`) and a
   run id with every call.
   - The skill is an asset of Base Agent API, in this repository, versioned
     and tested with the API it teaches.
   - Each running Bilimbi serves its own copy, as a zip carrying that
     server's address.
   - A Domain's or Extension's skill text is its `guides`, in its own
     repository, served through search.
   - A separate public skills repository may only mirror the served copy.
   - An MCP server is not part of this decision.

## Open decisions: defaults pending the owner

The owner has not yet decided these six questions. Each is written here with
its recommended default, and the default is what gets built until the owner
answers. Each one is marked as a default and none is settled.

- **D1. Who may approve an agent's draft.** *Default, pending the owner:*
  a new capability, `base.agent-draft.approve`, granted by default to the
  Tenant Owner and Core Administrator roles. The approver must also hold
  the capability the change itself needs, checked when they approve. A
  person may approve a draft their own agent prepared, because approval
  guards against agent mistakes and injected instructions, not against the
  person. An agent never approves anything.
- **D2. Who may connect an agent, and how far a connection may go.**
  *Default, pending the owner:*
  - every signed-in person may connect an agent to their own account;
  - a new connection starts at `read`;
  - the person may choose `draft` when approving the connection;
  - `write` stays unavailable until an operator raises the tenant's limit
    (setting `agent_access.max_level`, default `draft`);
  - an operator can switch agent access off for a tenant.
- **D3. An agent ID that differs from the approved one.** *Default,
  pending the owner:* record it, flag it on the connected-agents page as
  "also seen as …", and never refuse a request because of it. The
  connection's token grants access; the stated ID proves nothing.
- **D4. A helper script in the Bilimbi skill.** *Default, pending the
  owner:* ship a small standard-library-only Python 3 helper that signs
  in, keeps the token out of the conversation, and adds the agent and run
  headers, with plain HTTP calls documented as a fallback. The repository
  gains one Python file and one CI step that runs its tests.
- **D5. Auditing agent reads.** *Default, pending the owner:* yes. The
  dispatcher writes one audit action per API call, reads included, naming
  the person, the connection, the agent ID and the run (Decision 4).
- **D6. Default advice for adopters who want one central AI provider.**
  *Default, pending the owner:* company-managed AI seats from one provider,
  with single sign-on, plus the shared Bilimbi skill. Each person still
  connects with their own grant. A company-hosted chat front end is the
  option for a company that must use its own key or keep prompts on its
  own network. A provider's cloud chat app reaches only a Bilimbi with a
  public address; a Bilimbi on a private network needs an agent that runs
  on the person's own computer.

## Consequences

- Agents get no unattended identity. Routine work stays on named system
  principals (ADR 0017).
- Adding the bearer edge is a change to ADR 0016's caller list. Any further
  caller needs its own record.
- Operations inherit facades' validation and restrictions, but a facade that
  lacks its own capability check is protected by the dispatcher, not by
  itself. Moving those checks into facades remains worthwhile.
- The agent ID is self-reported. It labels audit and never grants access.
- Agent reads add one audit action each.
- Queued jobs cannot yet carry an agent facet, so no exposed operation
  enqueues one until that is designed.
- OAuth is implemented in-house, as a narrow subset: no implicit, password,
  client-credentials or OpenID Connect grants. The maintained Elixir
  provider library lacks the device grant and stores token values in plain
  text.
- Domain and Extension operations use meta-terms in keys, titles and
  guides; company wording belongs in configurable keywords.

## Alternatives considered

- **Model external agents as Belimbing agent employees.** This would need a
  row per agent, and model and effort change per session. It would also
  collide with the digital-worker meaning and its UI label.
- **A page that issues a long-lived personal token.** The secret would pass
  through the clipboard and chat transcripts, and the agent could not set
  itself up.
- **MCP as the first client surface.** Tool lists cost context in every
  session, and skills plus a helper cover coding agents. MCP can wrap the
  same API later.
- **A per-module API.** Every Domain would write controllers, and an agent
  would need module-specific instructions that drift.
