defmodule Bilimbi.Base.Audit.TestAuthorization do
  @moduledoc false

  @behaviour Bilimbi.Base.Audit.Authorization

  alias Bilimbi.Base.Tenancy.Scope

  @impl true
  def can?(%Scope{}, "admin.audit.log.manage"), do: true
  def can?(%Scope{}, capability) when is_binary(capability), do: false

  # A test names what its own process withholds; the answer is as live as the
  # process that set it.
  def withhold!(withheld), do: Process.put({__MODULE__, :withheld}, withheld)

  @impl true
  def withheld_fields(%Scope{}, types) when is_list(types) do
    Process.get({__MODULE__, :withheld}, %{}) |> Map.take(types)
  end
end
