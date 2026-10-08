defmodule Bilimbi.Base.Schedule.TestUserDirectory do
  @moduledoc false

  @behaviour Bilimbi.Base.PrincipalDirectory.Provider

  @impl true
  def principal_kind, do: :user

  @impl true
  def names(_scope, ids), do: Map.new(ids, &{&1, String.duplicate("日", 300)})
end
