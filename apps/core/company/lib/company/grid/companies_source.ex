defmodule Bilimbi.Core.Company.Grid.CompaniesSource do
  @moduledoc """
  The live companies of the scope's tenant, for the grid catalog: the same
  rows the companies list shows, tenant-scoped and without the soft-deleted.
  """

  @behaviour Bilimbi.Base.Grid.Source

  import Ecto.Query

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.Schema

  @impl true
  def query(scope) do
    from(c in Tenancy.scope_query(Schema, scope),
      where: is_nil(c.deleted_at),
      select: %{
        id: c.id,
        parent_id: c.parent_id,
        legal_entity_type_id: c.legal_entity_type_id,
        name: c.name,
        code: c.code,
        status: c.status,
        legal_name: c.legal_name,
        registration_number: c.registration_number,
        tax_id: c.tax_id,
        jurisdiction: c.jurisdiction,
        email: c.email,
        website: c.website,
        created_at: c.created_at,
        updated_at: c.updated_at
      }
    )
  end
end
