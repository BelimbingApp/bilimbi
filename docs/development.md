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

Independent checkouts should use separate development databases so one branch's
migrations do not prevent another branch from starting. All development Mix
commands read that checkout's ignored `.local/config.json`. Create or edit it
with the settings needed for that checkout, for example:

```json
{
  "database": {"name": "bilimbi_sbg_dev"},
  "https": {"host": "sbg.bilimbi.localhost", "port": 4001}
}
```

Both sections and their fields are optional. `database` accepts `name`, `host`,
`port`, `username` and `password`; `https` accepts `host`, `port` and the
automatically saved `root` checkout marker. Ports are JSON integers. Database
ports range from 1 to 65535; HTTPS backend ports range from 1024 to 65535.
Malformed JSON, unknown fields, invalid types and a marker for another checkout
stop the command with a diagnostic without displaying connection values.

Precedence is `DATABASE_URL` for the entire database connection, otherwise each
shell `PG*` variable overrides its corresponding JSON field, which overrides
the defaults above. `BILIMBI_DEV_HOST` and `PORT` similarly override saved HTTPS
fields. Environment variables set by Mise follow the same precedence; remove
an old `.mise.local.toml` database override when moving that setting into JSON.
Test and production environments do not read this development file.

Stop the checkout's server before editing its connection or HTTPS settings,
then create a new database with `mix ecto.create -r Bilimbi.Base.Repo` and start
it with `mix bilimbi.server`. Each database has its own accounts and migration
ledger. `.local/` is Git-ignored, and generated config files have mode 0600.
Keep these bootstrap credentials confined to local development.
Every checkout includes the versioned [`.local/README.md`](../.local/README.md)
with editing and startup instructions.

```bash
mix setup
mix bilimbi.server
```

Open the HTTPS address printed by `mix bilimbi.server`. The first local
checkout normally uses [https://bilimbi.localhost](https://bilimbi.localhost).

## Local HTTPS

`mix bilimbi.server` prepares local HTTPS before compiling and starting Phoenix,
then checks the certificate and OAuth issuer URL before announcing readiness.
It uses the shared system Caddy service, like Belimbing's shared ingress, with
mkcert certificates signed by your existing development CA. Install the local
prerequisites once:

```bash
sudo apt install caddy mkcert libnss3-tools
sudo systemctl enable --now caddy
mix bilimbi.server
```

Setup may ask for sudo to install trust and the site fragment. It adds an import
for `/etc/caddy/bilimbi/*.caddy` to the existing Caddyfile, validates the complete
configuration and reloads Caddy, preserving other sites. A failed validation or
reload restores the previous Caddyfile, site fragment and leaf certificates.
Ctrl+C stops Phoenix; the shared Caddy service keeps running.

The default address is `https://bilimbi.localhost`, with Phoenix listening only
on `127.0.0.1:4000`. Caddy accepts this site's requests from loopback and, on
NAT-mode WSL, the Windows virtual gateway. Other clients receive 403. No public
DNS, public certificate issuer or internet tunnel is involved. Phoenix trusts
Caddy's forwarded HTTPS scheme, uses secure session cookies and checks the
LiveView origin against the canonical HTTPS address. Local HSTS is disabled.

Multiple checkouts need no manual port or hostname assignment. Each plain
`mix bilimbi.server` selects a free backend port, reserves it in its Caddy site,
and saves the address in the `https` section of that checkout's ignored
`.local/config.json`. When `bilimbi.localhost` belongs to another
checkout, the new checkout gets `bilimbi-<checkout-fingerprint>.localhost`.
Repeats reuse the saved address; an already running instance is reported
without starting a duplicate or stopping any process. A stale/unhealthy server
in the same checkout is reported so it can be restarted explicitly. Installed
Caddy sites reserve ports while their checkouts are stopped or compiling.

To choose a particular hostname or port, override the automatic allocation:

```bash
BILIMBI_DEV_HOST=other.bilimbi.localhost PORT=4001 mix bilimbi.server
```

An explicitly chosen hostname or port that belongs to another instance stops
startup with a diagnostic. Subsequent Mix commands
read the saved instance address, so OAuth discovery agrees without
repeating environment variables. The hostname must be under `.localhost`;
browsers resolve these names to loopback,
and setup also adds the Linux hosts entry when needed. Under WSL, setup imports
only mkcert's public CA certificate into the current Windows user's root store.
An existing `CAROOT`, including Belimbing's shared Windows CA directory, is
reused. Restart a browser that was already running if its trust cache is stale.
Certificates and keys stay in ignored `.local/https/`; Caddy gets a protected
copy of the leaf key, and the CA private key stays in mkcert's CA directory.
Existing `.local/https/instance.json` settings migrate automatically into
`.local/config.json`; any existing canonical values win, database settings are
preserved, and the old instance file is removed after a successful save.
HTTPS verification reads discovery responses without storing `resource.json`.
This checkout-local state persists across `tmp/` cleanup; temporary test
checkouts and logs remain disposable under `tmp/`.

`mix bilimbi.server` in test or production does not configure local HTTPS.
Production uses its deployed Caddy configuration and release commands.

With the server running, verify the local HTTPS boundary without bypassing
certificate validation:

```bash
python3 scripts/test-local-https.py
python3 scripts/test-local-https-instances.py
```

This checks TLS, secure session cookies, redirects, OAuth URLs and the local
client allowlist.
The instance check creates and removes a temporary checkout's Caddy site to
verify automatic allocation, stable repeats, explicit conflicts and rollback
after a failed certificate validation. It requires sudo, like initial setup.

## Development database startup

`mix setup` fetches dependencies, creates the database, runs every installed
migration through `mix bilimbi.migrate`, and builds the web assets.
`mix bilimbi.server` runs that same migrate before it starts Phoenix, so a
module migration that arrives with a pull needs no separate command, and
once Phoenix is up it runs the development seed described below, so a fresh
clone needs nothing but `mix bilimbi.server`. A server that was already
running when a migration arrived shows a pending-migrations page naming what
to run until the database is migrated or the server is restarted;
`mix bilimbi.server --no-migrate` starts without migrating or seeding. The
baseline creates no tenant or company rows; platform-operator and
primary-company provisioning are explicit setup steps and numeric IDs carry no
runtime meaning.

The development seed, which `mix bilimbi.server` runs at every start-up and
`mix bilimbi.dev.seed` runs on its own, seeds installed reference data through
the production-seed ledger (what `mix bilimbi.seeds.run` does in production),
provisions the development platform tenant/company, and bootstraps
`ai@agent.my` / `bilimbi-dev` with `core_admin` through the
[shared bootstrap contract](deploy/README.md#bootstrap-contract-and-recovery).
It runs only in `dev`. Matching repeats preserve passwords and revoked roles
and add nothing to the server log. Existing identities without a bootstrap
receipt are never promoted: the server reports that in one line and starts,
with reference data seeded, and the plain command fails. Sign in with an
existing administrator or use a separate fresh development database.

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

`mix bilimbi.migrate` migrates without starting a server, which setup, tests
and an existing Belimbing database's adoption sequence use.

Run database tasks from the umbrella root. A single module's project cannot
see the whole composition graph, so `ModuleRegistry.complete_modules!/0`
refuses to migrate from inside a module, Domain, or Extension.

`mix bilimbi.server` checks the compiled module metadata before compiling or
starting Phoenix. The root alias loads the recovery task from source so Mix
does not compile dependencies just to find it. If the task finds stale or
missing workspace-graph metadata, it cleans the dependency builds, compiles
once, and verifies the resulting graph. This includes a pulled module that
introduces a dependency on a new app; unrelated compilation and startup
errors still stop startup with their original diagnostics.

After pulling new modules or dependency changes while the development server
is running, stop it and run `mix bilimbi.server` again. Phoenix’s code reloader
uses the dependency graph from startup; reloading a page does not refresh it.

Plain `mix compile`, `mix test`, and `mix phx.server` do not run this
preflight. If a changed workspace graph breaks one of those entry points,
run `mix clean --deps` before retrying it.

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
│   ├── media/                    # Uploaded assets and private subject attachments
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
