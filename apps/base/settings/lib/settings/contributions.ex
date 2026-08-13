defmodule Bilimbi.Base.Settings.Contributions do
  @moduledoc false

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionProvider

  @impl true
  def contributions do
    %{settings: %{definitions: %{}, runtime_claims: []}}
  end
end
