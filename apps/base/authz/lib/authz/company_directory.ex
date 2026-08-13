defmodule Bilimbi.Base.Authz.CompanyDirectory do
  @moduledoc "Lower-layer contract used to validate live company ownership without Base naming Core."

  alias Bilimbi.Base.Tenancy.Scope

  @callback company_ids(Scope.t()) :: [pos_integer()]
  @callback company_in_scope?(Scope.t(), pos_integer()) :: boolean()
end
