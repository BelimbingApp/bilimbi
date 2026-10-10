defmodule Bilimbi.Base.AgentApi.TestNotAnOperation do
  @moduledoc false

  # Has the right function but never declares the behaviour.
  def call(_key, _scope, _input), do: {:ok, %{}}
end
