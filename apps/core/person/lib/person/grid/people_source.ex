defmodule Bilimbi.Core.Person.Grid.PeopleSource do
  @moduledoc false
  @behaviour Bilimbi.Base.Grid.Source
  import Ecto.Query
  @impl true
  def query(scope) do
    from(p in Bilimbi.Base.Tenancy.scope_query(Bilimbi.Core.Person.Schema, scope),
      where: is_nil(p.retired_at),
      select: map(p, [:id, :full_name, :email, :phone, :created_at, :retired_at])
    )
  end
end
