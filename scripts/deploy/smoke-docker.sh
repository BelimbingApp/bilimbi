#!/usr/bin/env bash
# Isolated integration test on a disposable CI runner, never a production host.
set -euo pipefail
image=${1:?usage: smoke-docker.sh IMAGE}
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
test_dir=$(mktemp -d)
export BILIMBI_IMAGE=$image BILIMBI_ENV_FILE=$test_dir/release.env
export BILIMBI_PORT=14000
compose=(docker compose --project-name bilimbi --file "$root/scripts/deploy/compose.yaml")
cleanup() {
  "${compose[@]}" down --volumes >/dev/null 2>&1 || true
  docker rm -f bilimbi-smoke-postgres >/dev/null 2>&1 || true
  rm -rf -- "$test_dir"
}
trap cleanup EXIT
# Abort before cleanup could touch an operator's real installation.
[[ ${CI:-} == true ]] || { trap - EXIT; rmdir "$test_dir"; echo "Disposable CI runner required" >&2; exit 2; }
if [[ -n $(docker ps -aq --filter label=com.docker.compose.project=bilimbi) ]] || \
   [[ -n $(docker volume ls -q --filter name=bilimbi_state) ]] || \
   docker container inspect bilimbi-smoke-postgres >/dev/null 2>&1; then
  trap - EXIT
  rmdir "$test_dir"
  echo "Smoke resource names already exist; refusing to touch them" >&2
  exit 2
fi
cat > "$BILIMBI_ENV_FILE" <<'ENV'
DATABASE_URL=ecto://bilimbi:smoke-password@host.docker.internal:15432/bilimbi
SECRET_KEY_BASE=smoke-only-012345678901234567890123456789012345678901234567890123456789
BELIMBING_APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
PHX_HOST=localhost
POOL_SIZE=5
MAIL_HOST=localhost
MAIL_PORT=1025
MAIL_USERNAME=smoke
MAIL_PASSWORD=smoke
MAIL_TLS_MODE=starttls
MAIL_FROM_NAME=Bilimbi Smoke
MAIL_FROM_ADDRESS=smoke@example.com
ENV
chmod 0600 "$BILIMBI_ENV_FILE"
docker run -d --name bilimbi-smoke-postgres -p 15432:5432 \
  -e POSTGRES_USER=bilimbi -e POSTGRES_PASSWORD=smoke-password -e POSTGRES_DB=bilimbi \
  --health-cmd='pg_isready -U bilimbi -d bilimbi' --health-interval=1s \
  --health-retries=30 postgres:18-alpine
for _ in $(seq 1 30); do
  [[ $(docker inspect --format '{{.State.Health.Status}}' bilimbi-smoke-postgres) == healthy ]] && break
  sleep 1
done
[[ $(docker inspect --format '{{.State.Health.Status}}' bilimbi-smoke-postgres) == healthy ]]

printf 'bootstrap-password\n' | bash "$root/scripts/setup-docker.sh" install "$image" "$BILIMBI_ENV_FILE" \
  Operator Operations operations Admin admin@example.com
# Revoke the role and verify a matching setup cannot restore it or reset credentials.
"${compose[@]}" run --rm --no-deps -T app bin/bilimbi eval '
  :ok = BilimbiWeb.Release.start_without_workers()
  {:ok, user} = Bilimbi.Core.User.authenticate("admin@example.com", "bootstrap-password")
  {:ok, company} = Bilimbi.Core.Company.platform_operator_company()
  {:ok, scope} = Bilimbi.Base.Tenancy.scope(company.tenant_id)
  [assignment] = Bilimbi.Base.Authz.list_principal_role_assignments(scope, :user, user.id).entries
  {:ok, :unassigned} = Bilimbi.Base.Authz.unassign_role(scope, assignment.role_id, assignment.id)
'
printf 'changed-password\n' | bash "$root/scripts/setup-docker.sh" install "$image" "$BILIMBI_ENV_FILE" \
  Operator Operations operations Admin admin@example.com
bash "$root/scripts/setup-docker.sh" upgrade "$image" "$BILIMBI_ENV_FILE"
"${compose[@]}" run --rm --no-deps -T app bin/bilimbi eval '
  :ok = BilimbiWeb.Release.start_without_workers()
  {:ok, user} = Bilimbi.Core.User.authenticate("admin@example.com", "bootstrap-password")
  {:ok, company} = Bilimbi.Core.Company.platform_operator_company()
  {:ok, scope} = Bilimbi.Base.Tenancy.scope(company.tenant_id)
  [] = Bilimbi.Base.Authz.list_principal_role_assignments(scope, :user, user.id).entries
  {:ok, actions} = Bilimbi.Base.Audit.list_actions(scope)
  1 = Enum.count(actions, &(&1.event == "user.bootstrap.completed"))
'
echo 'Docker release smoke passed'
