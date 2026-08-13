defmodule Bilimbi.Base.ModuleRegistry.TestProvider do
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions, do: %{}
end

defmodule Bilimbi.Base.ModuleRegistry.UnknownConsumerTestProvider do
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions, do: %{unknown: []}
end

defmodule Bilimbi.Base.ModuleRegistry.NonPlainTestProvider do
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions, do: %{settings: fn -> :not_plain end}
end

defmodule Bilimbi.Base.ModuleRegistry.ThrowingTestProvider do
  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions, do: raise("provider failed")
end

defmodule Bilimbi.Base.ModuleRegistry.MissingBehaviourTestProvider do
  def contributions, do: %{}
end
