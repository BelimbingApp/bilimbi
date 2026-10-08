defmodule Bilimbi.Core.Company.Migrations.BackfillAuthzDecisionLogTenants do
  @moduledoc false

  # Rows a Bilimbi database logged before Authz gained
  # `base_authz_decision_logs.tenant_id` (`20261008070000`) take the tenant of
  # their company. A row with no company has no derivable tenant and stays
  # null; the platform operator's decision log page still lists it. An adopted
  # Belimbing database arrives with Belimbing's own backfill already applied.
  #
  # Company owns this rather than Authz: `core/company` declares its dependency
  # on `base/authz` and already contributes to an Authz table
  # (`20260811093957`), and `companies.tenant_id` is Company's column. Global
  # version order places it after both the Authz column migration and the
  # Company baseline, so the edge is declared, not assumed.
  use Ecto.Migration

  def up do
    schema = quote_identifier(prefix() || "public")

    execute("""
    UPDATE #{schema}.base_authz_decision_logs AS log
    SET tenant_id = company.tenant_id
    FROM #{schema}.companies AS company
    WHERE log.company_id = company.id AND log.tenant_id IS NULL
    """)
  end

  # A backfill is not undone: the derived tenant is as true as any other.
  def down, do: :ok

  defp quote_identifier(identifier) do
    ~s("#{String.replace(identifier, "\"", "\"\"")}")
  end
end
