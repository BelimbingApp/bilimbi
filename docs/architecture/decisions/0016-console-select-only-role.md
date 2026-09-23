# 16. Operator SQL console runs as a select-only PostgreSQL role

Date: 2026-09-23

## Status

Accepted

## Context

The operator SQL console is the one product surface that runs caller-authored
SQL, and its user is the platform operator, the person most worth auditing.
Until PR #781 its only effective write protection was a forbidden-keyword list
over the SQL text: the transaction it opened was meant to be read-only but set
the default for *later* transactions instead. #781 fixed that with
`SET TRANSACTION READ ONLY`, which made the boundary real, but it is still
application code guarding application code. A later edit to
`apps/base/database/lib/database/query_executor.ex` could weaken it without
anyone noticing, and the repo-level audit capture of ADR 0013 cannot see raw
SQL at all.

The captain's ruling (2026-09-23) chose the durable form: "right now 'the
console cannot write' is true because a check in our code says so; with a
read-only login it is true because the database will not allow otherwise."

## Decision

1. **Its own connection.** The console runs through
   `Bilimbi.Base.Database.ConsoleRepo`, a second Ecto Repo owned by Base
   Database and connected as a PostgreSQL role that holds `SELECT` and nothing
   else. Everything else in the platform keeps `Bilimbi.Base.Repo` unchanged.
   `SET ROLE` on the shared connection was rejected: membership lets the
   session switch back, so the boundary would again be the application's.
2. **Role provisioned outside the application.** A role is cluster state
   with a credential, so it is created by the cluster operator as a
   superuser, exactly like the application's own login, and named by the
   console's connection string (`CONSOLE_DATABASE_URL` in production, which
   boot requires). Migrations and seeds never create it.
3. **Every table, minus secrets declared by owners, applied by migrate.**
   `mix bilimbi.migrate` ends by granting the role `SELECT` on every table
   and view in the prefix, column by column where a schema contract's new
   optional `secret_columns/0` names credentials, tokens, or opaque session
   state, and revokes every other privilege it holds there. Core User hides
   `users.password`, `users.remember_token`, and
   `password_reset_tokens.token`; Base Session hides `sessions.payload`, which
   no operational listing exposes either. An allow-list of contract-declared
   tables was considered and rejected: contracts pin only the compatible
   baseline, so it would have hidden exactly the Bilimbi-only tables
   (schedule occurrences, postcode overrides, perf samples, Oban) an operator
   most needs to inspect. The cost is that Laravel's inert framework tables
   in an adopted database are readable, as they were through Belimbing's
   own console; nothing in Bilimbi declares their contents secret.
4. **Misconfiguration fails, never falls back.** Before every run the
   executor asks PostgreSQL, as the connected role, for every way the
   connection could write (superuser or creation flags, `CREATE` on the
   database or a schema, any write privilege on any relation) and refuses to
   run while the answer is not empty. The grant step likewise refuses a
   missing role or a console configured with the application's login.
5. **The text checks stay as messages.** The `SELECT`/`WITH` and forbidden
   keyword checks remain for early, readable refusals; the `READ ONLY`
   transaction remains for what privileges do not cover, such as temporary
   objects. Neither is the boundary any more.

## Consequences

- A write that passes every application check is refused by PostgreSQL on
  privileges (`permission denied for ...`), and the tests assert that refusal
  from the database rather than from a configuration value.
- `SELECT *` on a column-restricted table is refused; the console answers
  with the columns it may read so the operator names them instead.
- Every environment needs the role: CI creates it in the workflow, a
  developer creates it once per cluster, and an upgrading deployment must
  create it, set `CONSOLE_DATABASE_URL`, and run `mix bilimbi.migrate`. Each
  missing step fails loudly.
- The console sees only committed state. Its test connection is not
  sandboxed, so console tests create what they read outside the sandbox.

## Follow-ups

- Bulk-write audit capture (`*_all` and raw SQL outside the console) is the
  other half of the same ruling and is handled separately.
- Laravel's `jobs` and `failed_jobs` payloads in an adopted database are
  serialized PHP and could be declared secret by the module that owns that
  knowledge (ADR 0005 places it with Base Queue), through a contract whose
  `tables/0` is empty; nothing does so yet.
- The role keeps PostgreSQL's default `TEMP` privilege; temporary objects are
  session-local and the `READ ONLY` transaction refuses writing them.
