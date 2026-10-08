defmodule Bilimbi.ProofFactory.Widget.SchemaContract do
  @moduledoc """
  The schema contract of the Domain `Bilimbi.Core.Compatibility.InProcessDomain`
  mounts. It serves whatever `contract:` the mount declared, so one module
  stands in for a Domain with one baseline table, several, or a contribution
  to a Platform table.
  """

  @behaviour Bilimbi.Base.Database.SchemaContract

  @impl true
  def tables, do: Map.get(contract(), :tables, [])

  @impl true
  def contributions, do: Map.get(contract(), :contributions, [])

  defp contract do
    Application.fetch_env!(Bilimbi.Core.Compatibility.InProcessDomain.otp_app(), :schema_contract)
  end
end
