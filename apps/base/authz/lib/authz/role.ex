defmodule Bilimbi.Base.Authz.Role do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "base_authz_roles" do
    field :company_id, :id
    field :name, :string
    field :code, :string
    field :description, :string
    field :is_system, :boolean, default: false
    field :grant_all, :boolean, default: false
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @type t :: %__MODULE__{}

  @spec custom_changeset(pos_integer(), map()) :: Ecto.Changeset.t()
  def custom_changeset(company_id, attributes) do
    %__MODULE__{}
    |> cast(attributes, [:name, :code, :description])
    |> put_change(:company_id, company_id)
    |> put_change(:is_system, false)
    |> put_change(:grant_all, false)
    |> validate_required([:company_id, :name, :code])
    |> validate_length(:name, max: 255)
    |> validate_length(:code, max: 255)
    |> validate_length(:description, max: 1_000)
    |> validate_format(:code, ~r/^[a-z0-9_]+$/)
    |> unique_constraint([:company_id, :code], name: :base_authz_roles_company_id_code_unique)
    |> foreign_key_constraint(:company_id, name: :base_authz_roles_company_foreign)
    |> check_constraint(:company_id, name: :base_authz_roles_custom_company_check)
  end
end
