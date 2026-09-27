defmodule Bilimbi.Base.Authz.SystemPrincipalCapability do
  @moduledoc false

  use Ecto.Schema

  schema "base_authz_system_principal_capabilities" do
    field :company_id, :id
    field :principal, :string
    field :capability_key, :string
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @type t :: %__MODULE__{}
end
