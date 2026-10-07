# Ubuntu 26.04 production deployment

For normal installation, adoption and upgrades use
[`scripts/setup-native.sh`](../../scripts/setup-native.sh), following
[Deployment and initial setup](README.md). The sections below describe the
native adapter's build, configuration and underlying recovery steps. For
other Linux distributions use the [Docker deployment path](README.md#docker-setup).

This runbook installs one Bilimbi release on an Ubuntu 26.04 x86-64 host with
PostgreSQL 18 and Caddy. Build releases on **Ubuntu 26.04 for the same CPU
architecture** as the server. A release bundles Erlang and native libraries;
the production server needs no Elixir, Mix, Node, or source checkout.

Use a dedicated staging server and a verified database backup before upgrading
an existing installation. A binary rollback does not undo a database migration.
For a Belimbing database, follow [verify and adopt](../migrating-from-belimbing.md)
before the first Bilimbi migration.

## 1. Build and upload

Check out the exact platform revision. Mount each selected Domain or Extension
repository at `apps/domains/<id>` or `apps/extensions/<id>` **before** building.
The container build context copies these mounted sources; record their commit
IDs with the platform revision. A nested repository's `.git` metadata is
excluded, but its source is included.

```bash
scripts/deploy/build.sh 2026.09.30-1
scp dist/bilimbi-2026.09.30-1-ubuntu-26.04-amd64.tar.gz* \
  <ssh-user>@<server>:/tmp/
```

The build runs `mix deps.get --only prod`, compiles the complete discovered
composition, builds and digests web assets, then packages
`_build/prod/rel/bilimbi`. The output is a versioned tarball and SHA-256 file
in `dist/`. The Docker build requires a working Docker daemon and network
access to Ubuntu packages, mise, Hex, and binary asset downloads.

For CI, use an `ubuntu-26.04` x86-64 runner with the same mounted checkouts,
install the pinned `.mise.toml` toolchain, then run the equivalent commands:

```bash
mise trust && mise install
mise exec -- mix local.hex --force
mise exec -- mix local.rebar --force
MIX_ENV=prod mise exec -- mix deps.get --only prod
MIX_ENV=prod mise exec -- mix compile
(cd apps/web && MIX_ENV=prod mise exec -- mix assets.deploy)
MIX_ENV=prod mise exec -- mix release bilimbi
tar -C _build/prod/rel -czf "bilimbi-${VERSION}-ubuntu-26.04-amd64.tar.gz" bilimbi
sha256sum "bilimbi-${VERSION}-ubuntu-26.04-amd64.tar.gz" > "bilimbi-${VERSION}-ubuntu-26.04-amd64.tar.gz.sha256"
```

CI must arrange the Domain and Extension checkouts before dependency resolution;
the platform repository alone cannot package code that is absent from the build
workspace. Publish both artifacts from the same job.

## 2. Prepare the server once

Connect over SSH, then run:

```bash
sudo bash scripts/deploy/setup-ubuntu.sh
```

Copy the script to the server first if it has no source checkout. The script
installs PostgreSQL 18 from the PGDG apt repository, Caddy, a `bilimbi` system
user, and owned directories.
It prompts for a PostgreSQL role password only when creating the role. Save that
password in your secret store. The database and role are both named `bilimbi`.
PostgreSQL remains local; do not open port 5432 publicly.

Create `/etc/bilimbi/bilimbi.env` from
[`bilimbi.env.example`](../../scripts/deploy/bilimbi.env.example). Replace
every placeholder. Generate `SECRET_KEY_BASE` with
`mix phx.gen.secret` on a trusted build machine. Generate a fresh
`BELIMBING_APP_KEY` as `base64:` followed by the base64 encoding of 32 random
bytes. For example, on a trusted machine use
`printf 'base64:'; openssl rand -base64 32` and remove any trailing newline
from the generated value. When adopting a Belimbing database, set
`BELIMBING_APP_KEY` to that database's legacy `APP_KEY` so existing encrypted
settings remain readable. Preserve this key across deployments. Rotating it
requires decrypting and re-encrypting every stored encrypted setting with the
new key before deploying it; otherwise those settings cannot be read. Passwords in `DATABASE_URL`
must be percent-encoded. Restrict the file:

```bash
sudo install -o root -g root -m 0600 bilimbi.env /etc/bilimbi/bilimbi.env
```

The file stays outside each release. `DATABASE_URL`, `SECRET_KEY_BASE`,
`BELIMBING_APP_KEY`, `PHX_HOST`, `PORT`, `POOL_SIZE`, and the optional
`TRUSTED_PROXIES` are boot settings. The current Web
release also **requires** `MAIL_*` SMTP and sender variables at startup; its
mail adapter has not yet moved them into operator settings. Keep these secrets
only in the protected environment file, never in Git. Other operational
settings belong in Bilimbi's operator UI. Preserve `SECRET_KEY_BASE` across
deployments; rotating it invalidates signed sessions and queued actor jobs.

Install the unit and Caddy site:

```bash
sudo install -o root -g root -m 0644 scripts/deploy/bilimbi.service /etc/systemd/system/bilimbi.service
sudo install -o root -g root -m 0644 scripts/deploy/Caddyfile.example /etc/caddy/Caddyfile
sudoedit /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl daemon-reload
sudo systemctl enable caddy
sudo systemctl restart caddy
```

Replace `example.com` in Caddy with the public name in `PHX_HOST`. Point
DNS to this server and allow inbound 80/443 before expecting a certificate.
Caddy obtains and renews certificates and forwards LiveView WebSocket upgrades
through `reverse_proxy` automatically. If Cloudflare fronts the site, use
Full (strict) TLS, keep the origin reachable for certificate issuance, and
allow WebSockets. Do not use Flexible SSL.

The application listens on port 4000 by default. Restrict that port to the
local host with the VPS firewall; Caddy is the public entry. The provided unit
sets automatic restart, a file descriptor limit, memory and task caps, and
journald logging. Adjust resource limits for measured production load.
If `PORT` differs from 4000, change the Caddy upstream to the same value.

Bilimbi takes the client address from `X-Forwarded-For` only when the direct
peer is a trusted proxy, reading right to left past trusted hops; a header from
any other peer is ignored. `TRUSTED_PROXIES` lists those proxies as
comma-separated CIDRs and defaults to loopback (`127.0.0.0/8,::1/128`), which
matches the local Caddy upstream. Set it only when a proxy reaches Bilimbi
from another address. Login throttling, audit addresses and webhook sender
limits all use this client address, so a missing proxy entry makes every
client look like the proxy.

## 3. Deploy and verify

On the server, from a directory containing both uploaded artifacts:

```bash
sudo bash deploy.sh /tmp/bilimbi-2026.09.30-1-ubuntu-26.04-amd64.tar.gz 2026.09.30-1 5
sudo systemctl status bilimbi
sudo journalctl -u bilimbi -n 100 --no-pager
curl -fsS -o /dev/null -w '%{http_code}\n' https://<your-domain>/
```

Copy [`deploy.sh`](../../scripts/deploy/deploy.sh) to the server first. The
script verifies SHA-256, unpacks into `/opt/bilimbi/releases/<version>`, runs
`BilimbiWeb.Release.migrate()`, switches `/opt/bilimbi/current`, restarts the
service, and requires HTTP 200 from the local sign-in page at `/`. On a failed
health check it restores the previous symlink and restarts it. It keeps at
least the current and previous releases plus the newest requested count. A
failed first deployment stops the service. It never reverses migrated schema or data.

Use `sudo systemctl start|stop|restart|status bilimbi` for service control,
and `sudo journalctl -u bilimbi -f` for live logs. The first deploy should
precede `systemctl enable bilimbi`; enable it after successful verification.
For upgrades, build a new version, take a backup, upload, run the same deploy
command, then check HTTPS and the relevant workflows.

## 4. First-run data

Production seeds are separate from migrations. After the first healthy deploy:

```bash
sudo bash seed.sh
```

Copy [`seed.sh`](../../scripts/deploy/seed.sh) to the server first. The
production seed reconciles system roles and other installed module seeds;
it is repeatable. The development seed and its published test password must
never be used in production.

Provision the platform operator, its primary company, and the first account
through the public APIs. Copy [`bootstrap-admin.sh`](../../scripts/deploy/bootstrap-admin.sh)
to the server and substitute your own names, email, and unique company code.
The password is read privately and is not placed in shell history:

```bash
sudo bash bootstrap-admin.sh \
  "Platform operator" "Example Operations" "example_operations" \
  "Initial administrator" "admin@example.com"
```

Use an address you control and verify the account's email through the normal
application flow. If an existing Belimbing database already has administrators,
inspect its identity and role assignments before creating another.

Bootstrap now calls the shared one-time application command. It refuses an
existing installation without its own receipt. Matching repeats preserve
passwords and role revocations; a different administrator identity is refused.
Use the explicit `adopt` mode for a Belimbing database and `upgrade` for later
releases. Neither mode provisions an administrator.
