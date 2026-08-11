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
- Ecto mappings compatible with Belimbing's existing PostgreSQL tables and
  data conventions.

Bilimbi is a general business-application platform, not a fixed business
suite. An ERP is one intended kind of application that can be composed from its
Platform Baseline, business Domains, and deployment-owned Extensions.

Bilimbi is being built from the beginning by coding agents. The repository's
`AGENTS.md` and `DESIGN.md` are part of the engineering system: they describe
how the application should be extended and how it should feel to use.

## Current status

Bilimbi is in its foundation phase. The current repository is a clean Phoenix
application scaffold. The accepted target is a flat Mix umbrella rooted at
`bilimbi/`; the scaffold has not yet been converted. Base and Core will be
established first, while optional Domains and deployment-owned Extensions are
intentionally not implemented yet.

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

Useful commands:

```bash
mix format
mix test
mix precommit
```

`mix precommit` is the required final check for a change. It compiles with
warnings as errors, formats the project, and runs the test suite.

## Architecture at a glance

```text
bilimbi/                  # Mix umbrella root
├── base/                 # Platform infrastructure and shared contracts
├── core/                 # Required enterprise Domain
└── web/                  # Phoenix endpoint and shared UI shell
```

Future optional Domain and Extension sources will mount as direct umbrella
children, such as `bilimbi/people` or `bilimbi/sb_group`. See
[ADR 0001](./docs/architecture/decisions/0001-flat-bilimbi-umbrella-topology.md)
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

## Documentation

| Topic | Link |
|---|---|
| Agent and coding rules | [AGENTS.md](./AGENTS.md) |
| Product and interface design | [DESIGN.md](./DESIGN.md) |
| Flat umbrella topology | [ADR 0001](./docs/architecture/decisions/0001-flat-bilimbi-umbrella-topology.md) |
| Source Belimbing project | [BelimbingApp/belimbing](https://github.com/BelimbingApp/belimbing) |
| Phoenix documentation | [phoenix.hexdocs.pm](https://phoenix.hexdocs.pm/) |
| Elixir documentation | [hexdocs.pm/elixir](https://hexdocs.pm/elixir/) |

## License

Bilimbi is released under the [MIT License](./LICENSE).
