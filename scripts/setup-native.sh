#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: sudo setup-native.sh install ARCHIVE VERSION ENV_FILE CADDY_FILE TENANT COMPANY CODE ADMIN_NAME ADMIN_EMAIL" >&2
  echo "       sudo setup-native.sh adopt ARCHIVE VERSION ENV_FILE CADDY_FILE" >&2
  echo "       sudo setup-native.sh upgrade ARCHIVE VERSION" >&2
  exit 2
}
[[ $EUID -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
mode=${1:-}
case "$mode:$#" in install:10|adopt:5|upgrade:3) ;; *) usage ;; esac
archive=$(realpath -- "$2")
version=$3
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# Reject unsupported systems before making changes, including upgrades.
# shellcheck disable=SC1091
source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 26.04 ]] || { echo "Native setup supports Ubuntu 26.04 only" >&2; exit 2; }
[[ $(uname -m) == x86_64 ]] || { echo "Native setup supports x86-64 only" >&2; exit 2; }
exec 9>/run/lock/bilimbi-setup.lock
flock -n 9 || { echo "Another native deployment is running" >&2; exit 2; }

if [[ "$mode" != upgrade ]]; then
  env_file=$(realpath -- "$4")
  caddy_file=$(realpath -- "$5")
  [[ -f "$env_file" && -f "$caddy_file" ]] || usage
  # Repeated setup preserves operator configuration, including local service edits.
  for pair in "$env_file:/etc/bilimbi/bilimbi.env" "$caddy_file:/etc/caddy/Caddyfile"; do
    source_file=${pair%:*}
    target_file=${pair##*:}
    if [[ -f "$target_file" ]] && ! cmp -s "$source_file" "$target_file"; then
      echo "Configuration conflict at $target_file; edit it explicitly before repeating setup" >&2
      exit 2
    fi
  done
  bash "$root/deploy/setup-ubuntu.sh"
  if [[ "$env_file" != /etc/bilimbi/bilimbi.env ]]; then
    install -o root -g root -m 0600 "$env_file" /etc/bilimbi/bilimbi.env
  fi
  chown root:root /etc/bilimbi/bilimbi.env
  chmod 0600 /etc/bilimbi/bilimbi.env
  if [[ "$caddy_file" != /etc/caddy/Caddyfile ]]; then
    install -o root -g root -m 0644 "$caddy_file" /etc/caddy/Caddyfile
  fi
  if [[ ! -f /etc/systemd/system/bilimbi.service ]]; then
    install -o root -g root -m 0644 "$root/deploy/bilimbi.service" /etc/systemd/system/bilimbi.service
  fi
  caddy validate --config /etc/caddy/Caddyfile
  systemctl daemon-reload
fi

deployment_mode=upgrade
[[ "$mode" == adopt ]] && deployment_mode=adopt
bash "$root/deploy/deploy.sh" "$archive" "$version" 5 "$deployment_mode"
case "$mode" in
  install) bash "$root/deploy/bootstrap-admin.sh" "${@:6:5}" ;;
  adopt) bash "$root/deploy/seed.sh" ;;
esac
systemctl enable bilimbi
if [[ "$mode" != upgrade ]]; then
  systemctl enable caddy
  systemctl restart caddy
fi
echo "Native $mode complete"
