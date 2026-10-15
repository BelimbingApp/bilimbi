defmodule Bilimbi.Core.Person.Grid.RelationshipsSource do
  @behaviour Bilimbi.Base.Grid.Source
  import Ecto.Query
  @impl true
  def query(scope) do
    from(r in Bilimbi.Base.Tenancy.scope_query(Bilimbi.Core.Person.Relationship, scope),
      select:
        map(r, [
          :id,
          :person_id,
          :company_id,
          :relationship_type_id,
          :effective_from,
          :effective_to,
          :created_at,
          :deleted_at
        ])
    )
  end
end
