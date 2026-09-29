#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
ssh_port=${1:?usage: sudo setup-ubuntu.sh SSH_PORT TIME_ZONE}
time_zone=${2:?usage: sudo setup-ubuntu.sh SSH_PORT TIME_ZONE}
if ! [[ "$ssh_port" =~ ^[0-9]+$ ]] || ((ssh_port < 1 || ssh_port > 65535)); then
  echo "Invalid SSH port" >&2; exit 2
fi
[[ -f "/usr/share/zoneinfo/$time_zone" ]] || { echo "Unknown time zone" >&2; exit 2; }
# shellcheck disable=SC1091
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || { echo "Ubuntu 24.04 required" >&2; exit 2; }

apt-get update
apt-get install -y ca-certificates curl gnupg postgresql-common ufw unattended-upgrades caddy
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
install -d -o postgres -g postgres -m 0700 /var/backups/bilimbi
runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='bilimbi'" | grep -qx 1 || \
  runuser -u postgres -- createuser --pwprompt --no-superuser --no-createdb --no-createrole bilimbi
runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='bilimbi'" | grep -qx 1 || \
  runuser -u postgres -- createdb --owner=bilimbi bilimbi
timedatectl set-timezone "$time_zone"
timedatectl set-ntp true
systemctl enable --now postgresql unattended-upgrades
ufw allow "$ssh_port/tcp"
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
echo "Install bilimbi.env and the systemd/Caddy files from scripts/deploy before starting Bilimbi."
