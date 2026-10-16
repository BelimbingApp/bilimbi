defmodule Bilimbi.Core.Person.Grid.AffiliationsSource do
  @moduledoc false
  @behaviour Bilimbi.Base.Grid.Source
  import Ecto.Query
  @impl true
  def query(scope) do
    from(a in Bilimbi.Base.Tenancy.scope_query(Bilimbi.Core.Person.Affiliation, scope),
      select:
        map(a, [
          :id,
          :person_id,
          :company_id,
          :title,
          :email,
          :phone,
          :started_on,
          :ended_on,
          :legacy_employee_id,
          :created_at,
          :unlinked_at
        ])
    )
  end
end
