defmodule Bilimbi.Base.Authz.PrincipalCapability do
  @moduledoc false

  use Ecto.Schema

  schema "base_authz_principal_capabilities" do
    field :company_id, :id
    field :principal_type, :string
    field :principal_id, :id
    field :capability_key, :string
    field :is_allowed, :boolean, default: true
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @type t :: %__MODULE__{}
end
