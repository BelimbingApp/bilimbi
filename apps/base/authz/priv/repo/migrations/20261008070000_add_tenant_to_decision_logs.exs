defmodule Bilimbi.Base.Authz.Migrations.AddTenantToDecisionLogs do
  @moduledoc false

  # Belimbing `0100_01_11_000006_add_tenant_id_to_base_authz_decision_logs_table`
  # (upstream, after the first Authz baseline): the tenant a decision was made
  # in, read with an exact match by the tenant-scoped decision log page.
  #
  # Belimbing backfilled its pre-tenancy rows with its licensee tenant. Bilimbi
  # gives numeric ID 1 no meaning and has no equivalent constant, so rows a
  # fresh Bilimbi database logged before this column exist keep a null tenant
  # and stay out of every tenant's page. An adopted database arrives with
  # Belimbing's backfill already applied.
  use Ecto.Migration

  def change do
    alter table(:base_authz_decision_logs) do
      add :tenant_id, :bigint
    end

    create index(:base_authz_decision_logs, [:tenant_id],
             name: :base_authz_decision_logs_tenant_id_index
           )
  end
end
