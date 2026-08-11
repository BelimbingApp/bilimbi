# Bilimbi

Bilimbi is the Phoenix and Elixir implementation of the Belimbing application
platform. It is designed to preserve Belimbing's business model, product
principles, and PostgreSQL schema while using the BEAM runtime and Phoenix
conventions.

The project is MIT licensed. See [LICENSE](./LICENSE).

## What Bilimbi is

Bilimbi provides a durable foundation for building business applications:

- Base infrastructure for database access, authentication, authorization,
  tenancy, settings, auditability, and shared platform behaviour.
- Core business modules for users, companies, employees, addresses, and other
  required enterprise primitives.
- A Phoenix web interface using LiveView, HEEx, Tailwind CSS, and verified
  routes.
- Bilimbi-owned Ecto baselines compatible with Belimbing's existing PostgreSQL
  tables, constraints, and data conventions.

Bilimbi is a general business-application platform, not a fixed business
suite. An ERP is one intended kind of application that can be composed from its
Platform Baseline, business Domains, and deployment-owned Extensions.

Bilimbi is being built from the beginning by coding agents. The repository's
`AGENTS.md` and `DESIGN.md` are part of the engineering system: they describe
how the application should be extended and how it should feel to use.

## Current status

Bilimbi is in its foundation phase. The repository uses a conventional Mix
umbrella rooted at the repository, with Base, Core, and Web as its Platform
Baseline. The first Company slice owns Ecto migrations that can create the
current compatible Base Tenancy and Core Company schema, or verify and adopt an
existing Belimbing database. Optional Domains and deployment-owned Extensions
are intentionally not implemented yet.

The first major compatibility target is the existing Belimbing PostgreSQL
schema. Bilimbi should map that schema accurately instead of creating a second,
similar data model. Belimbing remains the reference for table names, durable
identities, existing data, and business meaning while the port is underway.

## Development setup

The repository pins the local Erlang and Elixir toolchain in `.mise.toml`.
Install those versions with mise, then run:

```bash
mix setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000).

`mix setup` creates the database, runs the Base and Core compatibility
migrations, and builds the web assets. The baseline creates no tenant or
company rows; platform-operator and primary-company provisioning are explicit
setup steps and numeric IDs carry no runtime meaning.

To use an existing Belimbing database, configure its connection and adopt it
instead of running fresh creation migrations:

```bash
mix bilimbi.schema.verify
mix bilimbi.schema.adopt
mix phx.server
```

Adoption refuses schema drift and records the verified baselines in
`bilimbi_schema_migrations`. Laravel's `migrations` table is never changed.

Useful commands:

```bash
mix format
mix test
mix bilimbi.migrate
mix bilimbi.migrations
mix bilimbi.schema.verify
mix precommit
```

`mix precommit` is the required final check for a change. It compiles with
warnings as errors, unlocks unused dependencies, formats the project, and runs
the test suite.

## Architecture at a glance

```text
apps/
├── base/                 # Platform infrastructure and shared contracts
├── core/                 # Required enterprise Domain
└── web/                  # Phoenix endpoint and shared UI shell
```

Future optional Domain and Extension sources will mount as direct umbrella
children, such as `apps/people` or `apps/sb_group`. See
[ADR 0001](./docs/architecture/decisions/0001-mix-umbrella-topology.md)
for the accepted topology and its lifecycle boundaries.

Base and Core are ownership boundaries, not superclass hierarchies. A domain
module exposes a small public API and hides its schemas, queries, and internal
workflow. Web modules call those APIs; business modules do not depend on the
web layer.

Views may be colocated with their LiveView module through `embed_templates` or
HEEx files, while remaining under `BilimbiWeb`. This keeps presentation close
to the workflow without mixing Phoenix concerns into the domain API.

## Compatibility with Belimbing

Compatibility means that Bilimbi can use the same PostgreSQL database and
preserve the same logical records. It does not mean copying Laravel classes or
reproducing Laravel internals.

The intended operating model is one active application runtime at a time. The
compatibility goal is a seamless schema and data-model transition, not
concurrent Laravel/Phoenix access or dual writes.

The compatibility work includes:

- exact table and column names;
- primary keys, foreign keys, sequences, indexes, and constraints;
- JSON and timestamp representations;
- soft-delete behaviour and status values;
- tenant, company, user, and employee relationships;
- polymorphic records and stable persisted identities;
- migration and seed data safety.

Ecto schemas and queries should be written against the compatibility contract.
Do not invent a cleaner parallel schema without an explicit migration decision.

The current contract uses `tenants.is_platform_operator` for the installation
operator and `tenant_primary_companies` for each tenant's designated company.
`companies.tenant_id` is always explicit and has no database default. ID 1 is
only historical migration input in Belimbing, never a Bilimbi runtime role.

Bilimbi-owned migrations live with their owning application below
`apps/base/priv/repo/migrations` and `apps/core/priv/repo/migrations`. Fresh
installations use `mix bilimbi.migrate`; existing databases use the explicit
verify-and-adopt workflow described in
[ADR 0002](./docs/architecture/decisions/0002-compatible-schema-baselines.md).

## Documentation

| Topic | Link |
|---|---|
| Agent and coding rules | [AGENTS.md](./AGENTS.md) |
| Product and interface design | [DESIGN.md](./DESIGN.md) |
| Mix umbrella topology | [ADR 0001](./docs/architecture/decisions/0001-mix-umbrella-topology.md) |
| Compatible schema baselines | [ADR 0002](./docs/architecture/decisions/0002-compatible-schema-baselines.md) |
| Source Belimbing project | [BelimbingApp/belimbing](https://github.com/BelimbingApp/belimbing) |
| Phoenix documentation | [phoenix.hexdocs.pm](https://phoenix.hexdocs.pm/) |
| Elixir documentation | [hexdocs.pm/elixir](https://hexdocs.pm/elixir/) |

## License

Bilimbi is released under the [MIT License](./LICENSE).
