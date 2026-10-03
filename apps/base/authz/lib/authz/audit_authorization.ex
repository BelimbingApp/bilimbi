defmodule Bilimbi.Base.Authz.AuditAuthorization do
  @moduledoc false

  @behaviour Bilimbi.Base.Audit.Authorization

  alias Bilimbi.Base.Authz

  @impl true
  def can?(%Bilimbi.Base.Tenancy.Scope{} = scope, capability) when is_binary(capability) do
    Authz.can(scope, capability).allowed
  end
end
