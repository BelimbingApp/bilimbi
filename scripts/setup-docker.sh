#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: setup-docker.sh install IMAGE ENV_FILE TENANT COMPANY CODE ADMIN_NAME ADMIN_EMAIL" >&2
  echo "       setup-docker.sh adopt IMAGE ENV_FILE" >&2
  echo "       setup-docker.sh upgrade IMAGE ENV_FILE" >&2
  exit 2
}
mode=${1:-}
case "$mode:$#" in install:8|adopt:3|upgrade:3) ;; *) usage ;; esac
[[ $(uname -s) == Linux ]] || { echo "Docker setup requires a Linux host" >&2; exit 2; }
export BILIMBI_IMAGE=$2
image_name=${BILIMBI_IMAGE##*/}
if [[ "$BILIMBI_IMAGE" != *@sha256:* && ( "$image_name" != *:* || "$image_name" == *:latest ) ]]; then
  echo "Use an explicit versioned image or digest, not an implicit/latest tag" >&2
  exit 2
fi
export BILIMBI_ENV_FILE
BILIMBI_ENV_FILE=$(realpath -- "$3")
[[ -f "$BILIMBI_ENV_FILE" ]] || usage
# Compose must not persist or interpolate credentials in its project .env.
[[ $(stat -c '%a' "$BILIMBI_ENV_FILE") == 600 ]] || { echo "ENV_FILE must have mode 0600" >&2; exit 2; }
exec 9<"$BILIMBI_ENV_FILE"
flock -n 9 || { echo "Another deployment is using this environment file" >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
compose=(docker compose --project-name bilimbi --file "$root/deploy/compose.yaml")
"${compose[@]}" config --quiet
docker image inspect "$BILIMBI_IMAGE" >/dev/null 2>&1 || docker pull "$BILIMBI_IMAGE"
previous=$({ "${compose[@]}" ps -q app | xargs -r docker inspect --format '{{.Image}}'; } | head -n 1)

run_release() {
  # Compose forwards stdin by default. Migration/adoption/seed commands must
  # not consume a password piped to the later bootstrap prompt.
  "${compose[@]}" run --rm --no-deps -T app bin/bilimbi eval "$1" </dev/null
}
if [[ "$mode" == adopt ]]; then
  run_release 'BilimbiWeb.Release.adopt()'
fi
run_release 'BilimbiWeb.Release.migrate()'
case "$mode" in
  install)
    IFS= read -rsp 'Initial admin password (blank for completed setup): ' bootstrap_password || bootstrap_password=
    echo
    printf '%s\n' "$bootstrap_password" | "${compose[@]}" run --rm --no-deps -T \
      -e "BOOT_TENANT_NAME=$4" -e "BOOT_COMPANY_NAME=$5" -e "BOOT_COMPANY_CODE=$6" \
      -e "BOOT_ADMIN_NAME=$7" -e "BOOT_ADMIN_EMAIL=$8" \
      app bin/bilimbi eval 'BilimbiWeb.Release.bootstrap()'
    unset bootstrap_password
    ;;
  adopt) run_release 'BilimbiWeb.Release.seed()' ;;
esac
healthy=false
if "${compose[@]}" up -d --no-deps app; then
  for _ in $(seq 1 30); do
    status=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 2 \
      "http://127.0.0.1:${BILIMBI_PORT:-4000}/" || true)
    if [[ "$status" == 200 ]]; then healthy=true; break; fi
    sleep 2
  done
fi
if [[ "$healthy" != true ]]; then
  echo "Health check failed; migrations and committed data are not reversed" >&2
  if [[ -n "$previous" ]]; then
    export BILIMBI_IMAGE=$previous
    "${compose[@]}" up -d --no-deps app
  else
    "${compose[@]}" stop app
  fi
  exit 1
fi
echo "Docker $mode complete: $BILIMBI_IMAGE"
