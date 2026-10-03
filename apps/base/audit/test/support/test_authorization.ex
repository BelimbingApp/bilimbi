defmodule Bilimbi.Base.Audit.TestAuthorization do
  @moduledoc false

  @behaviour Bilimbi.Base.Audit.Authorization

  alias Bilimbi.Base.Tenancy.Scope

  @impl true
  def can?(%Scope{}, "admin.audit.log.manage"), do: true
  def can?(%Scope{}, capability) when is_binary(capability), do: false
end
