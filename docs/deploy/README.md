# Deployment and initial setup

Use one entry point for your deployment: `scripts/setup-native.sh` or
`scripts/setup-docker.sh`. Each offers `install`, `adopt`, and `upgrade`.
Build artifacts separately; mount selected Domains and Extensions before
building so the release contains the complete composition.

| Mode | Behavior |
|---|---|
| `install` | Prepare/deploy, migrate, seed reference data, and provision the explicitly selected initial administrator |
| `adopt` | Verify and adopt a Belimbing schema, migrate, seed reference data, and retain existing identities and administrators |
| `upgrade` | Migrate and deploy; never provision an administrator or overwrite operator configuration |

The native adapter currently supports Ubuntu 26.04 x86-64. The Docker image
currently supports Linux amd64 and can run on other distributions with a
compatible Docker Engine and Compose. Native support for another distribution
requires its own tested installation adapter; do not rename an Ubuntu tarball
and assume its native libraries are compatible.

## Native setup

Follow [the Ubuntu environment and proxy guidance](ubuntu-26.04.md) to prepare
`bilimbi.env` and `Caddyfile` outside the source checkout. Configure DNS and
allow public HTTPS. Use a PostgreSQL connection to the intended target database.
The Ubuntu preparation helper creates a local PostgreSQL 18 role/database if
missing, prompting for its password only when the role is first created.

Build and upload the release and its checksum, along with the `scripts/` tree:

```bash
scripts/deploy/build.sh 2026.10.07-1
sudo bash scripts/setup-native.sh install \
  /tmp/bilimbi-2026.10.07-1-ubuntu-26.04-amd64.tar.gz 2026.10.07-1 \
  /secure/bilimbi.env /secure/Caddyfile \
  "Platform operator" "Example Operations" example_operations \
  "Initial administrator" admin@example.com
```

The entry point installs packages, protected configuration and the service,
deploys and checks local HTTP health, bootstraps the account, and enables the
application and proxy services. Repeat setup with the same identity to resume
after interruption. A blank password is accepted only after bootstrap completed.
Different existing configuration files are refused; edit them deliberately.
Existing service-unit edits are preserved. If supplying files already in their
installed locations, setup reuses them. The helpers under `scripts/deploy/`
remain implementation steps and recovery tools.

For an existing Belimbing database, back up and follow
[the adoption requirements](../migrating-from-belimbing.md), including its
legacy encryption key, then use:

```bash
sudo bash scripts/setup-native.sh adopt ARCHIVE VERSION ENV_FILE CADDY_FILE
```

Adoption runs structural and data-invariant verification before recording the
compatible baseline; it never chooses an administrator. For later releases:

```bash
sudo bash scripts/setup-native.sh upgrade ARCHIVE VERSION
```

## Docker setup

Use Linux with Docker Engine, Compose 2.30 or later, Bash, GNU coreutils,
util-linux (`flock`) and curl. Install these through your distribution's maintained packages. This
adapter does not install a container engine or reconfigure the host firewall.

Build a versioned runtime image separately:

```bash
scripts/deploy/build-image.sh 2026.10.07-1
```

Push to your chosen registry or transfer with `docker save` / `docker load`.
Pass the resulting versioned image reference or digest to setup. The image
contains Erlang, the application and runtime libraries; it runs as an
unprivileged user with a read-only root filesystem. Docker used by `build.sh`
still only builds a native tarball; `build-image.sh` builds the runtime image.

Provision PostgreSQL 18 separately, either as a managed database, a native
service, or an independently managed container with persistent storage and
backups. Create its database and role first. `DATABASE_URL` must be reachable
from the app container: `127.0.0.1` refers to that container, not the host.

Create a protected environment file outside the source checkout using
[docker.env.example](../../scripts/deploy/docker.env.example); set mode 0600.
Use the same required release settings described in the Ubuntu runbook.
Compose loads this file in **raw** format: write literal `KEY=value` lines,
without shell quotes, expansions, escapes or inline comments. Spaces and `$`
in values are literal. Never use this raw file as a shell script. See the
[Compose env-file contract](https://docs.docker.com/reference/compose-file/services/#format).

```bash
chmod 0600 /secure/docker.env
bash scripts/setup-docker.sh install bilimbi:2026.10.07-1 /secure/docker.env \
  "Platform operator" "Example Operations" example_operations \
  "Initial administrator" admin@example.com
```

Setup runs one-off release commands before starting the app, then requires
HTTP 200 from the local sign-in page. It uses a stable Compose project name
`bilimbi`; run from the same script tree on repeat and upgrades. The named
`bilimbi_state` volume holds app state, including the Geonames download cache.
Keep it across container replacement. PostgreSQL persistence is separately owned.

The app is published only at `127.0.0.1:4000` on the host. Configure your
HTTPS reverse proxy to forward there, including WebSocket upgrades. Override
the host port with `BILIMBI_PORT` if needed; the container port stays 4000.
Set `TRUSTED_PROXIES` to the actual proxy peer address seen by the app. With a
host proxy and Docker bridge networking this is commonly the bridge gateway;
inspect `docker network inspect bilimbi_default` and verify the address.
Container loopback alone does not trust a host proxy. Finish by checking HTTPS,
client-address handling, sign-in and email verification through your domain.

For adoption and upgrades:

```bash
bash scripts/setup-docker.sh adopt IMAGE /secure/docker.env
bash scripts/setup-docker.sh upgrade NEW_IMAGE /secure/docker.env
```

On a failed health check setup restores the previous container image, or stops
a failed first deployment. Binary rollback never reverses migrations or
committed data. Keep a verified backup and use staging before upgrades.
One installation per host is supported by these wrappers. Run only one
deployment operation at a time.

## Bootstrap contract and recovery

Both adapters call `BilimbiWeb.Release.bootstrap()`, which runs installed
reference seeds and `Bilimbi.Core.User.bootstrap_platform_admin/1`.
The password arrives on stdin, never in command arguments or the saved
environment file. Verify the administrator's email through the normal flow.

The User module locks account creation while proving the installation is
fresh. It refuses any existing user, including a company-less user, or an
existing platform operator unless its own completed receipt exists. It never
infers trust from user ID or creation order. Adopted and older installations
use their existing administrator workflows; there is no bootstrap promotion
or automatic repair of missing roles on an account.

The account, `core_admin` assignment in the primary company, durable receipt,
and retained `user.bootstrap.completed` console audit action commit in one
transaction. Failures roll back that transaction and can be retried. Matching
repeats preserve passwords, names, role revocations and operator settings;
different tenant/company identities or administrator email are refused. The
receipt remains even if the account is later deleted. Never remove it to
recover access; use an explicit, audited operator recovery procedure.

Reference seeds have their own ledger. Completed seeds are skipped. After
contribution changes, explicitly run `mix bilimbi.authz.reconcile` (or
`Bilimbi.Base.Authz.reconcile_system_roles()` through a release eval with
`BilimbiWeb.Release.start_without_workers()`). This refreshes configured role
definitions without restoring revoked account assignments.

Local development uses the same reference-seed and administrator bootstrap
through `mix bilimbi.dev.seed`, then runs module sample seeds. Migrate first.
Older development identities without a receipt are deliberately not promoted;
use existing administration/recovery or a separate fresh development database.
Never run the development seed or its published password in production.
