defmodule Bilimbi.Core.Company.Grid.LegalEntityTypesSource do
  @moduledoc "The legal entity types, global reference data, for the grid catalog."

  @behaviour Bilimbi.Base.Grid.Source

  import Ecto.Query

  alias Bilimbi.Core.Company.LegalEntityType

  @impl true
  def query(_scope) do
    from(t in LegalEntityType,
      select: %{id: t.id, code: t.code, name: t.name, is_active: t.is_active}
    )
  end
end
