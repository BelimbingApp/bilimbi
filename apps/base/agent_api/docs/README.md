# Base Agent API

Base Agent API holds the operations installed modules register for AI
agents that run outside Bilimbi, finds them by the words an agent types,
and calls them as a person with the checks the screens make
(ADR 0021, `docs/architecture/decisions/0021-agent-access-and-api-operations.md`).
No model runs inside Bilimbi: ranking is plain word matching.

## The model

A module registers operations and short guides through its `:agent_api`
contribution. An operation declares a stable key that begins with the
module's id, a title, a summary, keywords, whether it reads or writes, the
capability the matching page asks for, an input schema, and a handler. The
handler implements `Bilimbi.Base.AgentApi.Operation` and calls the module's
own facade with the scope it is given. The validator,
`Bilimbi.Base.AgentApi.ContributionValidator`, owns the contract and fails
boot on a malformed declaration; its moduledoc lists the rules. A module
that is not installed contributes nothing, so a deployment's operations are
exactly its installed modules' operations.

An agent's loop is three calls on `Bilimbi.Base.AgentApi`:

1. `search/3` ranks the operations and guides the scope's person may use by
   the words given (`Bilimbi.Base.AgentApi.Search`). With
   `include_unavailable: true` it also returns the ones the person lacks
   the capability for, so the agent can say what to ask for.
2. `describe/2` returns one operation's input and output schemas, its
   capability, how it would run, and its related guides. `guide/2`
   returns a guide's text.
3. `call/3` runs the operation through `Bilimbi.Base.AgentApi.Dispatcher`:
   input shape (`Bilimbi.Base.AgentApi.InputSchema`), then
   `Authz.can/4` for the operation's capability, then the handler. The
   facade's changesets, field restrictions and internal checks apply
   unchanged, and `Bilimbi.Base.AgentApi.Json` turns a restricted field
   into `{"restricted": true}`.

`Bilimbi.Base.AgentApi.Reach` decides which capabilities an operation may
stand on: a read stands on a `view`, `list` or `search` capability, and no
operation stands on an access-control capability (authorization
administration, impersonation, settings management, agent-connection
management).

## Safe writes

A write that declares `safe_write: true` implements `preview/3` and `commit/3`
as well as the read handler contract. Preview uses its own facade's validation
and returns a summary and `{field, from, to}` changes, including defaults; it
never writes business records. Commit calls the ordinary mutation facade and
returns `{record, path}`. No handler bypasses field restrictions or workflows.
Unsupported writes remain refused, and `call/3` always refuses writes.

`plan/2` takes an ordered list of string-keyed `{key, input}` objects. It
returns each validation outcome and, only if all are valid, a `plan_code` and
`expires_at`. The code is random and stored only as a hash. Storage contains
only input, preview and identity digests, never business values. A code binds
operations, exact inputs, tenant, person, signed-in company and connection.
Map order is irrelevant; operation order and JSON value types are significant.

`commit/3` takes that code and the same operations. It locks the code, rejects
expiry, reuse or a changed identity/input, rechecks live authorization and the
preview, then writes all operations and consumes the code in one transaction.
A later failure rolls back every write and mutation audit, leaving the code
unconsumed. Uniqueness can still change between preview and commit; a preview
is validation, not a reservation. Changed preview data requires a fresh plan.

The default lifetime is ten minutes and the default limit is twenty operations,
operator settings `agent_api.plan_expiry_seconds` and
`agent_api.plan_max_operations`. `authz.agent_writes_enabled` defaults to true
for each company. It is checked for the signed-in company and an employee's
employer. Company managers change it on the company page; turning it off stops
existing uncommitted plans too. The code proves the reviewed data, not human
consent; the native client refuses to commit without a local approval of that
plan, and Bilimbi does not verify it (ADR 0021).

The host serves the HTTP endpoints, connection authentication and the general
API request log; see `apps/web/docs/agent-api.md`. Client files stay in the
harness. Core supplies the first supported writes: company and employee create.

## Tests

`test/` holds a test domain owned by this package (`TestOperations`) and
covers the validator, the input schema, ranking, and search, describe and
call against real Authz grants. `apps/web/test/bilimbi_web/agent_api_test.exs`
checks the booted registry: every operation's capability is registered,
and the Core operations answer with the Companies and Employees pages'
capability checks and field restrictions.
