# Bilimbi

An open-source platform for building and running ownable operational systems. Traditionally, software is built by programmers who do not know much about the subject matter. With Bilimbi and the help of AI coding agents, the subject matter experts can build what they want without relying on programmers. 

## Motivation

In the age of AI, companies should own the business system they run on without the perpetual license fees. Business software is expensive, often inflexible, and carries vendor lock-in; Bilimbi empowers businesses to build, customize, and own their operational systems, removing the SMB digitization bottleneck so it is practical to ship production-grade systems with in-house subject matter experts.

## Kosong (Malay for empty) Architecture

Bilimbi is designed for AI as the programmers so that builders with minimum programming knowledge can build. It shipped with essential functions encapsulated as the `Base` and `Core`. `Domains` and `Extensions` are where the applications live.

- **Base** is the framework infrastructure: authz, audit, schedules, and other essentials
- **Core** contains the core modules: users, companies, employees, and address.
- **Domains** is where the subject matter applications live
- **Extensions** is for customization for specific use cases

## Add-ons: Domains and Extensions

The main repository is the platform. Business capabilities are add-ons in
their own repositories.

- A **Domain** is a business capability with meaning of its own, such as
  Factory. Repository `BelimbingApp/b-dom-<id>`, mounted at
  `apps/domains/<id>`.
- An **Extension** adapts the platform, a Domain, or another Extension to one
  company's needs. Repository `BelimbingApp/b-ext-<id>`, mounted at
  `apps/extensions/<id>`.
- The mount folder is the container ID with hyphens turned into underscores,
  so `b-ext-company-a` mounts at `apps/extensions/company_a`.
- Bilimbi discovers a mounted repository from its `bilimbi.container.exs`.
  Removing the folder removes the code from the next build and keeps its data.

To add Factory, from the Bilimbi root:

```bash
git clone https://github.com/BelimbingApp/b-dom-factory.git apps/domains/factory
mix deps.get
mix bilimbi.migrate
mix bilimbi.server
```

The rules for building an add-on are in
[the composition model](./docs/architecture/0010_composition-model.md) and
[`apps/domains/AGENTS.md`](./apps/domains/AGENTS.md).

## Install with AI

Paste this into your AI coding agent. It checks prerequisites, installs, and
verifies.

```text
Install Bilimbi (https://github.com/BelimbingApp/bilimbi) on this machine and
verify it runs.

1. Prerequisites. Confirm `git` is installed. Confirm `mise` is installed
   (https://mise.jdx.dev); it installs the pinned Erlang and Elixir. Confirm a
   PostgreSQL 18 server is running and note its host, port, and a role that
   can create databases. Stop and tell me what is missing.
2. Clone: `git clone https://github.com/BelimbingApp/bilimbi.git` and work
   inside the `bilimbi` folder for every following step.
3. Toolchain: run `mise trust` then `mise install`. It reads `.mise.toml`
   (Erlang 28.5, Elixir 1.20.3). Run every `mix` command below through
   `mise exec -- mix ...` unless mise is activated in the shell.
4. Database connection. The defaults in `config/dev.exs` expect role
   `bilimbi`, password `bilimbi_dev_ca658ad7d8b5`, host `localhost`, port
   `5433`, database `bilimbi_dev`. Either create that role with CREATEDB, or
   export `DATABASE_URL=postgres://USER:PASSWORD@HOST:PORT/bilimbi_dev` for
   the server you have. Use the same value in every later shell.
5. Setup: run `mix setup`. It fetches dependencies, creates the database,
   runs every installed migration, and builds the web assets.
6. Development identity: run `mix bilimbi.dev.seed`. It creates the platform
   tenant, a company, and the login `ai@agent.my` / `bilimbi-dev`.
7. Run: start `mix bilimbi.server` in the background and wait until it logs
   that the endpoint is running on port 4000.
8. Verify: `curl -sS -o /dev/null -w '%{http_code}' http://localhost:4000`
   must print 200. Then open http://localhost:4000 in a browser, sign in with
   the login from step 6, and confirm the workspace loads. Report the result
   and how to stop the server.
```

## Quick start

For people installing by hand. Requirements are in the next section.

1. Clone and enter the repository:

   ```bash
   git clone https://github.com/BelimbingApp/bilimbi.git
   cd bilimbi
   ```

2. Install the pinned toolchain:

   ```bash
   mise trust && mise install
   ```

3. Point Bilimbi at PostgreSQL. Create a role `bilimbi` with password
   `bilimbi_dev_ca658ad7d8b5` that can create databases on port 5433, or set
   `DATABASE_URL` to an existing server:

   ```bash
   export DATABASE_URL=postgres://USER:PASSWORD@localhost:5432/bilimbi_dev
   ```

4. Create the database, run migrations, build assets, and seed a login:

   ```bash
   mix setup
   mix bilimbi.dev.seed
   ```

5. Start the server and open [http://localhost:4000](http://localhost:4000).
   Sign in with `ai@agent.my` and `bilimbi-dev`.

   ```bash
   mix bilimbi.server
   ```

Setup for real tenants, production mail, and the developer commands are in
[`docs/development.md`](./docs/development.md).

## Requirements

- Erlang/OTP 28.5 and Elixir 1.20.3, pinned in `.mise.toml`.
- PostgreSQL 18.
- Node.js 22 or later, only to run the LiveView hook tests in
  `mix precommit`.
- Linux or macOS. CI runs on Ubuntu 26.04. Windows works through WSL2.

More documentation is in [`docs/`](./docs/README.md). Bilimbi is released
under the [MIT License](./LICENSE).

Production installation on Ubuntu 26.04 is covered by the
[deployment guide](./docs/deploy/ubuntu-26.04.md).
