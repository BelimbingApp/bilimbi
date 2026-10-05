#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 26.04 ]] || { echo "Ubuntu 26.04 required" >&2; exit 2; }

apt-get update
apt-get install -y ca-certificates curl gnupg postgresql-common caddy
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --batch --yes --dearmor -o /etc/apt/keyrings/postgresql.gpg.tmp
chmod 0644 /etc/apt/keyrings/postgresql.gpg.tmp
mv /etc/apt/keyrings/postgresql.gpg.tmp /etc/apt/keyrings/postgresql.gpg
printf 'deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt %s-pgdg main\n' "$VERSION_CODENAME" > /etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y postgresql-18
id bilimbi >/dev/null 2>&1 || useradd --system --home /var/lib/bilimbi --shell /usr/sbin/nologin bilimbi
install -d -o root -g root -m 0755 /opt/bilimbi/releases
install -d -o bilimbi -g bilimbi -m 0750 /var/lib/bilimbi
install -d -o root -g bilimbi -m 0750 /etc/bilimbi
runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='bilimbi'" | grep -qx 1 || \
  runuser -u postgres -- createuser --pwprompt --no-superuser --no-createdb --no-createrole bilimbi
runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='bilimbi'" | grep -qx 1 || \
  runuser -u postgres -- createdb --owner=bilimbi bilimbi
systemctl enable --now postgresql
echo "Install bilimbi.env and the systemd/Caddy files from scripts/deploy before starting Bilimbi."
