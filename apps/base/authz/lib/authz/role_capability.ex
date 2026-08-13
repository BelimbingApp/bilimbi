defmodule Bilimbi.Base.Authz.RoleCapability do
  @moduledoc false

  use Ecto.Schema

  schema "base_authz_role_capabilities" do
    field :role_id, :id
    field :capability_key, :string
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end
end
