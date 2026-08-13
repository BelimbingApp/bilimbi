defmodule Bilimbi.Base.ModuleRegistry.TestProvider do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions, do: %{}
end

defmodule Bilimbi.Base.ModuleRegistry.UnknownConsumerTestProvider do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions, do: %{unknown: []}
end

defmodule Bilimbi.Base.ModuleRegistry.NonPlainTestProvider do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions, do: %{settings: fn -> :not_plain end}
end

defmodule Bilimbi.Base.ModuleRegistry.ThrowingTestProvider do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions, do: raise("provider failed")
end

defmodule Bilimbi.Base.ModuleRegistry.MissingBehaviourTestProvider do
  @moduledoc false

  def contributions, do: %{}
end
