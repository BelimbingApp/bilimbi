#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
[[ $# -eq 5 ]] || { echo "usage: sudo bootstrap-admin.sh TENANT_NAME COMPANY_NAME COMPANY_CODE ADMIN_NAME ADMIN_EMAIL" >&2; exit 2; }
[[ -f /etc/bilimbi/bilimbi.env ]] || { echo "Missing release environment" >&2; exit 2; }
set -a
# shellcheck disable=SC1091
source /etc/bilimbi/bilimbi.env
set +a
export BOOT_TENANT_NAME=$1 BOOT_COMPANY_NAME=$2 BOOT_COMPANY_CODE=$3
export BOOT_ADMIN_NAME=$4 BOOT_ADMIN_EMAIL=$5
unset PHX_SERVER
IFS= read -rsp 'Initial admin password (blank for completed setup): ' bootstrap_password || bootstrap_password=
echo
printf '%s\n' "$bootstrap_password" | runuser -u bilimbi -- \
  /opt/bilimbi/current/bin/bilimbi eval 'BilimbiWeb.Release.bootstrap()'
unset bootstrap_password
