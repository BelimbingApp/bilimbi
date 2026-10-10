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

## What is not here yet

Only reads run; every write answers `{:error, :writes_not_enabled}`. There
is no HTTP surface, connection, token or agent identity on the scope, and
no audit row per call. ADR 0021 describes how each of those arrives.

## Tests

`test/` holds a test domain owned by this package (`TestOperations`) and
covers the validator, the input schema, ranking, and search, describe and
call against real Authz grants. `apps/web/test/bilimbi_web/agent_api_test.exs`
checks the booted registry: every operation's capability is registered,
and the Core operations answer with the Companies and Employees pages'
capability checks and field restrictions.
