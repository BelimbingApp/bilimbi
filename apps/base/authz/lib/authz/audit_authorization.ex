defmodule Bilimbi.Base.Authz.AuditAuthorization do
  @moduledoc false

  @behaviour Bilimbi.Base.Audit.Authorization

  alias Bilimbi.Base.Authz

  @impl true
  def can?(%Bilimbi.Base.Tenancy.Scope{} = scope, capability) when is_binary(capability) do
    Authz.can(scope, capability).allowed
  end

  @impl true
  def withheld_fields(%Bilimbi.Base.Tenancy.Scope{} = scope, types) when is_list(types) do
    Authz.withheld_fields_by_type(scope, types)
  end
end
