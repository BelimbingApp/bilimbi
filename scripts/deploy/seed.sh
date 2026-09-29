#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
[[ -f /etc/bilimbi/bilimbi.env ]] || { echo "Missing release environment" >&2; exit 2; }
set -a
# shellcheck disable=SC1091
source /etc/bilimbi/bilimbi.env
set +a
unset PHX_SERVER
runuser -u bilimbi -- /opt/bilimbi/current/bin/bilimbi eval 'BilimbiWeb.Release.seed()'
