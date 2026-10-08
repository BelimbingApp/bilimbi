defmodule Bilimbi.Base.Authz.Migrations.AddTenantToDecisionLogs do
  @moduledoc false

  # Belimbing `0100_01_11_000006_add_tenant_id_to_base_authz_decision_logs_table`
  # (upstream, after the first Authz baseline): the tenant a decision was made
  # in, read with an exact match by the tenant-scoped decision log page.
  #
  # Belimbing backfilled its pre-tenancy rows with its licensee tenant. Bilimbi
  # gives numeric ID 1 no meaning and has no equivalent constant, so rows a
  # fresh Bilimbi database logged before this column take the tenant of their
  # company. A row with no company has no derivable tenant and stays null; the
  # platform operator's decision log page still lists it. An adopted database
  # arrives with Belimbing's backfill already applied.
  #
  # Base does not depend on Core, so the backfill runs only where Core's
  # `companies` table exists; a Base-only database has no company to read.
  use Ecto.Migration

  def change do
    alter table(:base_authz_decision_logs) do
      add :tenant_id, :bigint
    end

    execute(backfill_from_company(), "SELECT 1")

    create index(:base_authz_decision_logs, [:tenant_id],
             name: :base_authz_decision_logs_tenant_id_index
           )
  end

  defp backfill_from_company do
    companies = qualified_table("companies")

    """
    DO $backfill$
    BEGIN
      IF to_regclass('#{String.replace(companies, "'", "''")}') IS NOT NULL THEN
        UPDATE #{qualified_table("base_authz_decision_logs")} AS log
        SET tenant_id = company.tenant_id
        FROM #{companies} AS company
        WHERE log.company_id = company.id AND log.tenant_id IS NULL;
      END IF;
    END
    $backfill$
    """
  end

  defp qualified_table(table_name) do
    case prefix() do
      nil -> quote_identifier(table_name)
      migration_prefix -> "#{quote_identifier(migration_prefix)}.#{quote_identifier(table_name)}"
    end
  end

  defp quote_identifier(identifier), do: "\"#{String.replace(identifier, "\"", "\"\"")}\""
end
