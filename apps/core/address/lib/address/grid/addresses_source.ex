defmodule Bilimbi.Core.Address.Grid.AddressesSource do
  @moduledoc "The live addresses of the scope's tenant, for the grid catalog."

  @behaviour Bilimbi.Base.Grid.Source

  import Ecto.Query

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address.Schema

  @impl true
  def query(scope) do
    from(a in Tenancy.scope_query(Schema, scope),
      where: is_nil(a.deleted_at),
      select: %{
        id: a.id,
        label: a.label,
        phone: a.phone,
        line1: a.line1,
        line2: a.line2,
        locality: a.locality,
        postcode: a.postcode,
        country_iso: a.country_iso,
        verification_status: a.verification_status,
        created_at: a.created_at
      }
    )
  end
end
