# Belimbing-to-Bilimbi Porting Stages

**Document Type:** Team delivery roadmap
**Status:** Provisional and stage-gated
**Last Updated:** 2026-09-27

The AI team ports capabilities in dependency order, not by translating files
or racing through a module list. Each stage exits only when its contracts,
schema, tests, documentation, and operational path are coherent in Bilimbi.
Database ownership, dependency, migration, verification, and adoption follow
the normative [Database Architecture](architecture/database.md).

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

The capabilities are Tenancy, Company, Geonames, Address, Employee, and User. Exact ordering is determined by the source inventory and
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

**State:** Modules shipped: Tenancy, Company, Geonames, Address, Employee, and
User. The exit-gate bullets are open until the steward confirms each against
the tree; reference-data import stays operational work.

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

**State:** Modules shipped: Authz, Session, Settings, Audit, and the Core User
integrations. The exit-gate bullets are open until the steward confirms each
against the tree.

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

**State:** Shipped: Datetime and Locale, Menu, Queue, Schedule, Dashboard,
Workflow, and telemetry/performance (Perf), plus System, Tiling, and Artifacts.
Media, Cache, and Integration have no module. The exit-gate bullets are open
until the steward confirms each against the tree.

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

**Purpose:** Introduce real optional business Domains as independent
repositories on the composition model in
[`architecture/0010_composition-model.md`](architecture/0010_composition-model.md).

A Domain is one repository mounted at `apps/domains/<id>`; Bilimbi discovers
it with no list naming it, its migrations run through the one ledger from the
host closure, and its own CI checks out a pinned Platform revision, mounts the
repository, and runs the Platform's precommit both mounted and absent. Port
one Domain at a time. A second real Domain is the test of whether shared
Domain conventions are justified.

**Exit gate per Domain:**

- install/remove source composition is deterministic, proven by the
  repository's mounted and absent CI jobs and a missing-dependency refusal;
- dependencies point only to allowed lower layers or declared, business-
  justified same-layer modules, and discovery rejects the rest;
- migrations and durable data remain safe when source code is absent, through
  the migration provenance record;
- the Domain works through public Base/Core contracts;
- its complete tests travel with its module directories and run under the
  Platform's precommit.

**State:** First Domain, Factory (`BelimbingApp/b-dom-factory`: Inventory,
Product Definition, Production Execution), shipped 2026-09-26 with each gate
item covered by its CI; see the rollout plan
`plans/domain-extension-layer-rollout.md`, Phase 3. The second-Domain test is
open.

## S6 — Extensions and distribution hardening

**Purpose:** Prove independent development, nested-Git delivery, upgrades,
diagnostics, and company-owned Extensions, whose ownership, visibility, and
licensing are independent of their architectural role.

**Exit gate:**

- repositories mount modules without central child lists (met: discovery,
  the Web host closure, and the `bilimbi` release);
- version, dependency, and update diagnostics are clear to operators
  (partly met: discovery names each graph error, and the composition lock's
  pinned manifest refuses a changed revision, mounted set, or lock; upgrade
  guidance is open);
- migration ordering and cleanup remain safe across installed sources (met:
  one ledger with migration provenance; unmounting keeps data);
- Extensions cannot create hidden upward or peer dependency layers: upward
  edges are rejected, and a peer edge exists only when declared, acyclic, and
  justified under 0010 (met);
- release, upgrade, rollback, and provenance workflows are documented and
  tested (partly met: release migrate and seed commands, rollback task, and
  provenance are documented and tested; a production-profile release boot in
  CI and an upgrade workflow are open).

**State:** First Extension, a customer Extension's source connector,
shipped 2026-09-26 with mounted, absent, and removal CI jobs; see
the rollout plan, Phase 4. The open gate items above remain.

## Stage-change rule

Only the coordination steward proposes a stage transition, and only the
integration steward records evidence for its gates. The user approves material
scope changes. Starting research for the next stage is allowed when read-only;
starting its implementation is not.

### Recorded scope changes

- **2026-09-26 — S5 and S6 started ahead of S2–S4.** The user approved
  starting the Factory build after the composition proof, before the S2, S3,
  and S4 gates closed; the approval is quoted in the intent of Bilimbi
  [pull request 812](https://github.com/BelimbingApp/bilimbi/pull/812) and
  the later Phase 2 pull requests. The scope change: S5 and S6 gate evidence
  is recorded per repository, in the mounted repository's own CI against a
  pinned Platform revision, rather than inside Bilimbi; S0's composition
  kernel was extended with nested-root discovery, the composition lock, route
  overlap rejection, and migration provenance to make that possible. S2–S4
  keep their gates and their order for the Platform itself.
