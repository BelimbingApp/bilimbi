# Belimbing-to-Bilimbi Porting Stages

**Document Type:** Team delivery roadmap
**Status:** Provisional and stage-gated
**Last Updated:** 2026-08-12

The AI team ports capabilities in dependency order, not by translating files
or racing through a module list. Each stage exits only when its contracts,
schema, tests, documentation, and operational path are coherent in Bilimbi.

## Per-capability pipeline

Every capability follows the same pipeline:

1. **Inventory:** Identify Belimbing ownership, durable identities, tables,
   migrations, data invariants, public workflows, dependencies, and tests.
2. **Contract:** Decide the Bilimbi module owner, descriptor dependencies,
   public API/read models, exact compatibility contract, migration/adoption
   behavior, and explicit deferrals.
3. **Implement:** Build inside one physical deep-module boundary. Preserve
   business meaning without copying Laravel architecture.
4. **Verify:** Add focused public-contract, tenant-boundary, schema, migration,
   and failure-path tests.
5. **Adapt:** Add Phoenix UI only through the public API, following
   `DESIGN.md`; do not expose private schemas to LiveView.
6. **Review:** Use a different agent for architecture/compatibility review and,
   where UI exists, UX/accessibility review.
7. **Integrate:** Apply shared-file changes, replay a fresh PostgreSQL schema,
   verify adoption where relevant, run `mix precommit`, and commit one coherent
   unit.

Skipping a pipeline step requires an explicit task-card deferral and steward
approval.

## S0 — Engineering and compatibility kernel

**Purpose:** Make AI-authored work safe to compose and verify.

Includes the umbrella, physical deep-module packaging, module discovery,
shared Repo, independent migration ledger, schema verification/adoption,
explicit tenancy, root engineering rules, and this team board.

**Exit gate:**

- descriptor graph and migration discovery are deterministic and tested;
- fresh schema and Belimbing adoption paths fail safely on drift;
- Base and Core boundaries are physical package boundaries;
- coordination and path ownership are documented;
- the full precommit gate is green.

**State:** Functionally established; keep open only for defects discovered by
real modules.

## S1 — Platform Baseline business identity

**Purpose:** Establish the required records and reference data on which later
business workflows depend.

Current/forthcoming capabilities include Tenancy, Company, Geonames, Address,
Employee, and User. Exact ordering is determined by the source inventory and
declared module graph. GeoNames reference import is operational work, not a
schema migration. Employee precedes User where the canonical foreign-key order
requires it.

**Exit gate:**

- every included module has an accepted source inventory and Bilimbi contract;
- fresh Bilimbi migrations reproduce the canonical current schema;
- existing Belimbing structure can be verified and adopted without drift;
- all runtime identity is explicit—no semantic numeric IDs;
- tenant/company boundaries and soft-delete policy are tested;
- required reference/bootstrap data has an idempotent, observable operational
  path separate from structural migrations;
- public APIs hide schemas and private queries;
- the full precommit and fresh-schema gates are green.

**State:** In progress.

## S2 — Access and governance

**Purpose:** Port authentication, authorization, session/current-scope,
settings ownership, and audit identity after Core identity is stable.

Likely capability owners include Base Authz, Session, Settings, Audit, and Core
User integrations. The source inventory must decide exact boundaries before
implementation tasks are created.

**Exit gate:**

- authenticated Phoenix routes carry one explicit current scope;
- custom roles have live company ownership and system roles are company-less;
- permissions, tenant boundaries, and soft-deleted owners are tested;
- settings and audit records preserve canonical durable shapes;
- no credential or provider configuration resolves from tenant identity alone;
- security review and precommit are green.

## S3 — Operational platform services

**Purpose:** Port the required cross-cutting services that make the baseline a
usable business platform.

Candidate areas include Locale/DateTime, Menu/Routing, Media, Queue/Schedule,
Cache, PDF, Dashboard, Integration, Workflow, telemetry/performance, and
support tooling. Each is admitted only after inventory proves it is required
and identifies its proper Base/Core owner.

**Exit gate:**

- admitted services have narrow APIs and deterministic discovery where needed;
- optional infrastructure degrades honestly without weakening business rules;
- background work is supervised, observable, retry-safe, and testable;
- Web shell contributions remain consistent and accessible;
- operational setup and failure recovery are documented.

## S4 — AI and workflow runtime

**Purpose:** Port Belimbing's AI/agent capabilities only after identity,
authorization, settings, audit, and operational foundations are trustworthy.

**Exit gate:**

- employee/agent identities do not rely on historical numeric IDs at runtime;
- provider credentials resolve through explicit owning-company context;
- delegated operations preserve actor, tenant, authorization, and audit scope;
- tools and workflows have bounded contracts, cancellation, and failure
  reporting;
- security, concurrency, and recovery reviews are green.

## S5 — Optional Domains

**Purpose:** Introduce the first real optional business Domain only after Base
and Core are stable.

Port one Domain bundle at a time. Its physical container and child modules use
the same descriptor discovery and nested-Git boundary as Base/Core. A second
real Domain is the test of whether shared Domain conventions are justified.

**Exit gate per Domain:**

- install/remove source composition is deterministic;
- dependencies point only to allowed lower layers or declared sibling modules;
- migrations and durable data remain safe when source code is absent;
- the Domain works through public Base/Core contracts;
- its complete tests travel with its module directories.

## S6 — Extensions and distribution hardening

**Purpose:** Prove independent development, nested-Git delivery, upgrades,
diagnostics, and deployment-owned Extensions.

**Exit gate:**

- distribution bundles can mount modules without central child lists;
- version/dependency/update diagnostics are clear to operators;
- migration ordering and cleanup remain safe across installed sources;
- Extensions cannot create hidden upward or peer dependency layers;
- release, upgrade, rollback, and provenance workflows are documented and
  tested.

## Stage-change rule

Only the coordination steward proposes a stage transition, and only the
integration steward records evidence for its gates. The user approves material
scope changes. Starting research for the next stage is allowed when read-only;
starting its implementation is not.
