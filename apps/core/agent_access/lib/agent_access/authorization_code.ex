defmodule Bilimbi.Core.AgentAccess.AuthorizationCode do
  @moduledoc false
  use Ecto.Schema
  @derive {Inspect, except: [:code_hash, :code_challenge]}
  schema "core_agent_authorization_codes" do
    field(:connection_id, :integer)
    field(:code_hash, :binary)
    field(:code_challenge, :string)
    field(:redirect_uri, :string)
    field(:expires_at, :utc_datetime)
    field(:used_at, :utc_datetime)
    timestamps(type: :utc_datetime)
  end

  def __audit_redacted_fields__, do: [:code_hash, :code_challenge]
end
