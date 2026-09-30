defmodule Bilimbi.Base.Artifacts.OtherTestOwner do
  @moduledoc false
  @behaviour Bilimbi.Base.Artifacts.Owner
  @impl true
  def artifact_owner_id, do: "test/documents"
  @impl true
  def authorize(_, _, _, _), do: :ok
end
