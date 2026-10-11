defmodule Bilimbi.Base.AgentApi.TestReadOnlyHandler do
  @moduledoc false

  # Implements the behaviour but exports no preview/3, so it cannot back a write.
  @behaviour Bilimbi.Base.AgentApi.Operation

  @impl true
  def call(_key, _scope, _input), do: {:ok, %{}}
end
