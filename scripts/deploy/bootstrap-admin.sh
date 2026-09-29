#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
[[ $# -eq 5 ]] || { echo "usage: sudo bootstrap-admin.sh TENANT_NAME COMPANY_NAME COMPANY_CODE ADMIN_NAME ADMIN_EMAIL" >&2; exit 2; }
[[ -f /etc/bilimbi/bilimbi.env ]] || { echo "Missing release environment" >&2; exit 2; }
read -rsp 'Initial admin password: ' ADMIN_PASSWORD
echo
[[ -n "$ADMIN_PASSWORD" ]] || { echo "Password is required" >&2; exit 2; }
set -a
# shellcheck disable=SC1091
source /etc/bilimbi/bilimbi.env
set +a
export ADMIN_PASSWORD
export BOOT_TENANT_NAME=$1 BOOT_COMPANY_NAME=$2 BOOT_COMPANY_CODE=$3
export BOOT_ADMIN_NAME=$4 BOOT_ADMIN_EMAIL=$5
unset PHX_SERVER
runuser -u bilimbi -- /opt/bilimbi/current/bin/bilimbi eval '
  {:ok, _} = Application.ensure_all_started(:web)
  {:ok, result} = Bilimbi.Core.Company.provision_platform_operator(
    System.fetch_env!("BOOT_TENANT_NAME"),
    %{name: System.fetch_env!("BOOT_COMPANY_NAME"),
      code: System.fetch_env!("BOOT_COMPANY_CODE")})
  {:ok, scope} = Bilimbi.Base.Tenancy.scope(result.tenant.id)
  email = System.fetch_env!("BOOT_ADMIN_EMAIL")
  {:ok, users} = Bilimbi.Core.User.list_company_users(scope, result.company.id)
  user =
    case Enum.find(users, &(&1.email == email)) do
      nil ->
        {:ok, created} = Bilimbi.Core.User.register_user(
          scope, result.company.id,
          %{name: System.fetch_env!("BOOT_ADMIN_NAME"), email: email,
            password: System.fetch_env!("ADMIN_PASSWORD")})
        created
      existing -> existing
    end
  role = Enum.find(Bilimbi.Base.Authz.list_roles(scope), &(&1.code == "core_admin")) ||
    raise "core_admin role missing; run production seed first"
  {:ok, _} = Bilimbi.Base.Authz.assign_role(
    scope, result.company.id, :user, user.id, role.id)
  IO.puts("Initial administrator ready: " <> email)
'
unset ADMIN_PASSWORD
