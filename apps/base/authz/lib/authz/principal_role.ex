defmodule Bilimbi.Base.Authz.PrincipalRole do
  @moduledoc false

  use Ecto.Schema

  schema "base_authz_principal_roles" do
    field :company_id, :id
    field :principal_type, :string
    field :principal_id, :id
    field :role_id, :id
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @type t :: %__MODULE__{}
end
