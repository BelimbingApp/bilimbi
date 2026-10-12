# ADR 0021: External agents act for a person through granted connections and self-registered API operations

**Document Type:** Architecture Decision Record
**Status:** Accepted
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
itself stays free of AI and is only the API: the work, the files and the
person's review happen in the agent's harness. The API runs the same
operations and checks as the screens, an agent can do what its person can
do and nothing more, the person sees and agrees to every change before it
is written, and every call is logged.

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

**Everything happens in the harness; Bilimbi is the API.** A person asks
their agent for any task, and the agent discovers the available operations,
schemas and business guides to carry it out through the API. The plugin
teaches connection, discovery and safe execution; task planning belongs to
the agent.

- Files stay in the harness, for example photos taken on a phone and handed
  to the agent. Bilimbi never receives files.
- The review and report page is a local page on `127.0.0.1`, served by the
  native Bilimbi program (Decision 9). Review happens at the desktop; a
  phone only supplies files.
- Bilimbi hosts no review page and keeps no work sessions.

1. **A connection is an OAuth grant owned by one person.** Bilimbi is its
   own authorization server. Any signed-in person may connect an agent to
   their own account. A connection binds the person, the company they
   approved it in, and that company's tenant, with an end date and the
   agent ID shown at approval. Core Agent Access (`core/agent_access`)
   owns connections and their tokens.
   - Bilimbi has many independent adopters, so the person gives the agent
     their server's address once. The client then discovers the server
     through OAuth authorization-server metadata (RFC 8414) plus a Bilimbi
     descriptor, and signs in with the device authorization grant
     (RFC 8628) under one public client id that every Bilimbi accepts.
   - In the device grant, the agent shows a code, and the person approves
     in Bilimbi on a page that names the stated agent ID.
   - Access tokens are opaque, last one hour and are stored only as hashes.
     Refresh tokens rotate, and replaying a rotated one revokes the
     connection.
   - There is no shared or service-account token.
   - A connection cannot be approved or used under impersonation.

2. **The bearer edge is the second caller of the authentication seam.**
   `BilimbiWeb.AgentAuth` proves the token, the connection, the company,
   the tenant and the person, with the browser edge's proof, then calls
   `Authentication.sign_in/4` with an `:agent` facet. The person is the
   actor (`type: :user`). The sealed facet names the connection and the
   agent ID stated on that request. Domain code reads it only through
   `Scope.actor/1`. `delegate/1` refuses a facet scope.

3. **An agent can do what its person can do, and no more.** For a facet
   scope, `Authz.can/4` decides for the person against live grants, then
   denies:
   - every platform capability (`:denied_agent_platform`);
   - every access-control capability: role, grant, field-restriction and
     system-principal administration, impersonation, settings management,
     and agent-connection management;
   - every write, while the company has switched agent writes off
     (`:denied_agent_writes_off`). A read verb is `view`, `list` or
     `search`; any other verb, an unknown one included, is a write.

   `scope_actor/1` carries the facet. Workflow human actions refuse a
   facet, so an agent never approves anything.

4. **One API request log, and the existing audit.** Every incoming API
   call, reads included, is one row in a general API request log owned by
   the platform, not by agents: the operation, the outcome, the person,
   the connection, the stated agent ID, the run and the trace id are
   ordinary fields. Outgoing calls can use the same log later. It does not
   store request or result bodies by default, because they can carry
   secrets and pay. A write's changes are recorded by the existing
   mutation audit as the person's rows (`actor_type "user"`), joined to
   the request by its trace id. The native Bilimbi program calls the
   API, so its calls are logged too; work done without the API, such as a
   server-side task, is covered by the audit alone. The `"agent"` actor
   type keeps its Belimbing meaning.

5. **Modules register operations; Base exposes them.** `:agent_api` is a
   peer consumer validated by `Bilimbi.Base.AgentApi.ContributionValidator`.
   - An entry declares a key, a title, a summary, keywords, `kind`
     (`:read` or `:write`), the capability the matching screen asks for,
     an input schema, and a handler that implements
     `Bilimbi.Base.AgentApi.Operation`, belongs to the declaring OTP
     application, and calls its own facade with the scope it receives. A
     write's handler also implements `preview/3`.
   - Modules may also contribute short guides.
   - A module that is not installed contributes nothing.
   - No module adds API routes. The host serves `/api/v1` and `/oauth`.

6. **Calls check what the screens check, and never more widely.** The
   dispatcher runs these steps in order:
   - validate the input's shape;
   - ask `Authz.can(scope, capability)`, the same key the screen's route or
     event asks;
   - for a write, check the plan code (Decision 8);
   - call the handler, so the facade's changesets, field restrictions and
     internal checks apply unchanged.

7. **Discovery is one search.** `search/3` ranks the operations and guides
   within the person's reach by the words given, deterministically and
   without a model. `describe/2` returns one operation's schemas and
   guides. The Bilimbi skill teaches search, then describe, then call, and
   lists no operations.

8. **Writes go dry run, go, write, report.**
   - The agent asks the API for a dry run. It validates the changes and
     returns the change plan (each record and field, before and after) and
     a plan code bound to that plan, the person and the input.
   - The agent shows the plan on the local review page, where the person
     can edit, comment, answer questions and give their go.
   - On the go, the agent calls the write carrying the plan code. Bilimbi
     refuses it if the input or the records' current values no longer
     match the plan.
   - The same local page then shows the report, with links into Bilimbi so
     the person can check each change.

   The go itself is not proven to Bilimbi. The agent acts as the person,
   with the person's own permissions, and the API request log records the
   run.

   Domain workflows still apply: a change that needs approval when made on
   a screen enters the same approval workflow when an agent makes it. There
   is no separate permission for agent changes.

9. **The client is one native Bilimbi program and a skill, not a protocol
   server.** The program has `login <address>`, profiles for more than one
   server, `search`, `describe`, `call` and `logout`. It signs in with the
   device grant, keeps the token in the operating system's credential store
   and out of the conversation, sends the agent ID
   (`harness/model-ver-effort`) and a run id with every call, and serves
   the local review and report page. It needs no other runtime.
   - The program and the skill are packaged as thin plugins for each agent
     harness, Codex first.
   - The skill is versioned and tested with the API it teaches.
   - A Domain's or Extension's skill text is its `guides`, in its own
     repository, served through search.
   - An MCP server is not part of this decision.

## The owner's decisions

- **D1 and D2. Who may connect, and how writes are agreed.** Anyone may
  connect an agent, and it can do what the person can do (Decision 3).
  Writes follow dry run, go, write, report (Decision 8), and a company can
  switch agent writes off.
- **D3. An agent ID that differs from the approved one.** Record it, flag
  it on the connected-agents page as "also seen as …", and never refuse a
  request because of it. The token grants access; the stated ID proves
  nothing.
- **D4. The client.** One native Bilimbi program plus the skill,
  packaged as thin plugins per agent harness, with the Codex plugin first
  (Decision 9).
- **D5. Logging.** One general API request log for every call, reads
  included, and the existing mutation audit for changes (Decision 4).
- **D6. One central AI provider for a company.** Deferred. People connect
  their own AI accounts for now. Connections stay per person and do not
  assume one provider, so a central option can be added later.

## Build order

Each job is its own change.

1. Foundation: self-registration, search, describe and read calls, in
   process.
2. The door: the HTTP endpoint, discovery (RFC 8414 plus a Bilimbi
   descriptor), OAuth device sign-in with one public client id, and the
   general API request log.
3. The native Bilimbi program and the Codex plugin: `login <address>`,
   profiles, the operating system's credential store, search, describe
   and call, the agent and run headers, the local review and report page,
   and the skill.
4. Safe writes on the API: dry run and plan code, creating a company and a
   person, and their guides.
5. End-to-end verification of discovery, local review, API writes and reports.

## Consequences

- Agents get no unattended identity. Routine work stays on named system
  principals (ADR 0017).
- Adding the bearer edge is a change to ADR 0016's caller list. Any further
  caller needs its own record.
- Operations inherit facades' validation and restrictions, but a facade that
  lacks its own capability check is protected by the dispatcher, not by
  itself. Moving those checks into facades remains worthwhile.
- The agent ID is self-reported. It labels the log and never grants access.
- Every API call, reads included, adds one request-log row.
- Queued jobs cannot yet carry an agent facet, so no exposed operation
  enqueues one until that is designed.
- OAuth is implemented in-house, as a narrow subset: no implicit, password,
  client-credentials or OpenID Connect grants. The maintained Elixir
  provider library lacks the device grant and stores token values in plain
  text.
- Domain and Extension operations use meta-terms in keys, titles and
  guides; company wording belongs in configurable keywords.
- Supported writes declare `safe_write: true` and implement preview/commit.
  The earlier `approval` contribution field is retired; a bound, expiring,
  single-use plan code gates every write. The native client refuses to commit
  a plan the person has not approved in its local review.
- Bilimbi cannot tell whether the person really gave the go; only the native
  client enforces it, locally. It relies on
  the person's own permissions, the plan code and the request log.

## Alternatives considered

- **Model external agents as Belimbing agent employees.** This would need a
  row per agent, and model and effort change per session. It would also
  collide with the digital-worker meaning and its UI label.
- **A page that issues a long-lived personal token.** The secret would pass
  through the clipboard and chat transcripts, and the agent could not set
  itself up.
- **MCP as the first client surface.** Tool lists cost context in every
  session, and a skill plus the native program cover coding agents. MCP
  can wrap the same API later.
- **A per-module API.** Every Domain would write controllers, and an agent
  would need module-specific instructions that drift.
- **Drafts approved under a separate permission.** An agent's write would
  wait as a draft for someone holding an "approve agent drafts"
  capability. The person who asked for the change is the one who should
  agree to it, and domain workflows already route changes that need
  someone else's approval.
- **A review page and work sessions hosted by Bilimbi.** Files and
  drafts would have to move into Bilimbi, and every harness would depend
  on a Bilimbi page. A local page in the harness keeps Bilimbi an API.
- **An audit log only for agents.** A separate agent log would duplicate
  the request facts every API caller needs and split one trail in two.
