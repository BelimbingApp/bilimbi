# Development guide

The root [`README.md`](../README.md) has the quick start. This page holds the
operational detail behind it: toolchain, database setup, provisioning real
tenants, the developer commands, an architecture map, and production mail.

## Toolchain and database

The repository pins the local Erlang and Elixir toolchain in `.mise.toml`,
which also sets `PGPORT=5433` for a local PostgreSQL 18 cluster. Install the
pinned versions with `mise install`.

`config/dev.exs` connects as role `bilimbi` with password
`bilimbi_dev_ca658ad7d8b5` to `localhost:5433/bilimbi_dev`, unless
`DATABASE_URL` is set, in which case the URL wins. The `PGUSER`, `PGPASSWORD`,
`PGHOST`, `PGPORT`, and `PGDATABASE` variables override the individual
defaults. The test environment uses the same role and a `bilimbi_test`
database.

```bash
mix setup
mix bilimbi.server
```

Open [http://localhost:4000](http://localhost:4000).

`mix setup` fetches dependencies, creates the database, runs every installed
migration through `mix bilimbi.migrate`, and builds the web assets. The
baseline creates no tenant or company rows; platform-operator and
primary-company provisioning are explicit setup steps and numeric IDs carry no
runtime meaning.

`mix bilimbi.dev.seed` seeds installed reference data, provisions the development
platform tenant/company, and bootstraps `ai@agent.my` / `bilimbi-dev` with
`core_admin` through the [shared bootstrap contract](deploy/README.md#bootstrap-contract-and-recovery).
It runs only in `dev`. Matching repeats preserve passwords and revoked roles.
Existing identities without a bootstrap receipt are refused rather than
promoted; use existing administration or a separate fresh development database.

## Provisioning identity

After a fresh migration, establish explicit operator identity with:

```bash
mix bilimbi.platform.provision \
  --tenant-name "Platform operator" \
  --company-name "Example Operations" \
  --company-code "example_operations"
```

The operation is idempotent: rerunning it resolves the existing marked tenant
and primary-company assignment rather than relying on a numeric ID.

Provision a customer tenant and its primary company atomically with:

```bash
mix bilimbi.tenant.provision \
  --tenant-name "Acme tenant" \
  --company-name "Acme Sdn. Bhd." \
  --company-code "acme"
```

## Useful commands

```bash
mix format
mix test
mix bilimbi.migrate
mix bilimbi.migrations
mix bilimbi.schema.verify
mix bilimbi.seeds.run
mix help bilimbi.platform.provision
mix help bilimbi.tenant.provision
mix help bilimbi.server
mix precommit
```

Run database tasks from the umbrella root. A single module's project cannot
see the whole composition graph, so `ModuleRegistry.complete_modules!/0`
refuses to migrate from inside a module, Domain, or Extension.

`mix bilimbi.server` checks the compiled module metadata before starting
Phoenix. If it finds stale or missing workspace-graph metadata, it rebuilds
the dependencies once and retries; other startup errors are reported without
automatic recovery.

`mix precommit` is the required final check for a change. It compiles the
umbrella with warnings as errors, strictly compiles each discovered module and
the Web host (`mix compile.strict`), unlocks unused dependencies, formats the
project, runs the LiveView hook tests in Node (`mix assets.test`), runs every
installed module's tests and the Web host's integration tests, and verifies
module contributions.
The hook tests need Node.js 22 or
later, with npm, on the `PATH`; `.mise.toml` does not pin it.

`mix precommit.test` runs every discovered module's tests in its own Mix
project, plus the Web host's integration tests. It reports each package's wall
time, including compilation and database setup. Profiling arguments reach every
package: `mix precommit.test --slowest 10 --slowest-modules 5`. Elixir's
`--slowest` enables trace mode and serial execution, so use a normal full
precommit run when comparing total elapsed time. Suites remain sequential
because compatibility tests temporarily mount source and refresh the shared
build graph. Local path dependencies use the test environment consistently to
avoid rebuilding their test support between host and package runs.

The Web host loads its helper and every discovered module bridge through
`apps/web/test_bootstrap/test_helper.exs` before compiling tests. Elixir 1.20.3's
helper loader otherwise stops at the first warning; the bootstrap keeps all
helpers loaded and preserves the normal warning diagnostics.

See [the precommit profile](plans/2026-10-02-precommit-profile.md) for the one
measured before/after comparison, profiler findings, and shared-machine limits.

A release built with `mix release` has no Mix. Migrate and seed it with
`bin/bilimbi eval "BilimbiWeb.Release.migrate()"` and
`bin/bilimbi eval "BilimbiWeb.Release.seed()"`.

To size the internationalisation backlog, run `.github/scripts/i18n_scan.py`. It
is a report-only inventory of user-facing string literals not wrapped in
Gettext, per module (`--samples N`, `--dump-high`); no CI step runs it and it
never fails a build.

## Architecture at a glance

```text
apps/
├── base/                         # Mandatory composition application
│   ├── bilimbi.container.exs     # Declares the Base layer
│   ├── artifacts/                # Private documents, PDF generation, retention
│   ├── audit/                    # Mutation and action history
│   ├── authz/                    # Capability, role, grant, and decision engine
│   ├── dashboard/                # Dashboard page, catalogue and layout
│   ├── database/                 # The one Repo, audit capture, console
│   ├── datetime/                 # Time display and clocks
│   ├── grid/                     # Field-and-link catalog and flexible columns on list pages
│   ├── locale/                   # Locale and localization
│   ├── menu/                     # Navigation from module contributions
│   ├── module_registry/          # Descriptor discovery and installed-module registry
│   ├── perf/                     # Performance health
│   ├── principal_directory/      # Who a principal is, across modules
│   ├── queue/                    # Durable job queue
│   ├── schedule/                 # Recurring occurrences on the queue
│   ├── session/                  # Opaque durable session persistence
│   ├── settings/                 # Immutable definitions and scoped values
│   ├── system/                   # Read-only instance facts (System Info)
│   ├── tenancy/                  # Tenant scope and operator resolution
│   ├── tiling/                   # Tiled workspace and saved layouts
│   ├── ui/                       # Shared components, layouts, Design Library
│   └── workflow/                 # Status configuration, transitions, history
├── core/                         # Mandatory composition application
│   ├── bilimbi.container.exs     # Declares the Core layer
│   ├── address/                  # Addresses with Geonames normalization
│   ├── company/                  # Companies, departments, primary companies
│   ├── compatibility/            # Migration ledger, verification, adoption
│   ├── employee/                 # Employees and employee types
│   ├── geonames/                 # Country, region, postcode, city reference data
│   ├── user/                     # Accounts, credentials, notifications
│   └── user_administration/      # Cross-module user administration read
├── domains/                      # Mount root for Domain repositories
├── extensions/                   # Mount root for Extension repositories
└── web/                          # Phoenix endpoint and host integration
```

The complete physical boundary of a module is its directory, such as
`apps/base/tenancy/`, not a directory below its `lib/`. Its source begins at
`apps/base/tenancy/lib/tenancy.ex` while the Elixir namespace remains
`Bilimbi.Base.Tenancy`. The same rule applies to every declared module.

A composition container never lists child packages by name. Every immediate
child directory containing `bilimbi.module.exs` is an installed module; the
shared discovery code validates all installed descriptors and generates the
container's local Mix path dependencies. Mounting a directory is the
source-installation action; dependency resolution and compilation still run
afterward.

The discovery helper belongs to `apps/base/module_registry/mix/` and is
covered by that package's formatter and tests. Mix writes its validated,
resolved module position and graph fingerprint into OTP application metadata;
a shared compiler refreshes that metadata across all module packages whenever
the installed descriptor set changes. Runtime migration discovery consumes
that approved order instead of maintaining a second graph algorithm.

The descriptor is the source of truth for stable module ID, layer, OTP
application ID, namespace, declared module dependencies, and migration
contribution. Discovery rejects malformed or missing descriptors, duplicate
stable or OTP IDs, missing dependencies, cycles, container/layer mismatches,
and upward dependency edges. Modules are ordered dependency-first with stable
module ID as the deterministic tie-breaker.

Optional Domains and Extensions are independent repositories mounted under
`apps/domains/<id>/` and `apps/extensions/<id>/`. See
[the composition model](./architecture/0010_composition-model.md) and
[ADR 0003](./architecture/decisions/0003-physical-deep-module-packages.md).

Base and Core are ownership boundaries, not superclass hierarchies. A domain
module exposes a small public API and hides its schemas, queries, and internal
workflow. LiveViews are UI adapters owned by the module whose workflow they
present, colocated with their templates; they call the module API and never
bypass it. Business modules do not depend on the web host.

## Production mail delivery

Production uses SMTP with mandatory authentication and certificate verification.
Set these environment variables before the release starts:

| Variable | Purpose |
|---|---|
| `MAIL_HOST` | SMTP relay hostname. |
| `MAIL_PORT` | Relay port (`587` for STARTTLS or commonly `465` for implicit TLS). |
| `MAIL_USERNAME` / `MAIL_PASSWORD` | SMTP credentials. |
| `MAIL_TLS_MODE` | `starttls` or `implicit_tls`; unencrypted delivery is not supported. |
| `MAIL_FROM_NAME` / `MAIL_FROM_ADDRESS` | Sender identity used for product email. |

An absent or invalid value stops a production release during configuration, so a
password-reset request cannot be the first time a mail misconfiguration is
discovered. Development uses Swoosh's local mailbox and test uses its test
adapter instead.
