defmodule Bilimbi.Core.Company.Schema do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}

  schema "companies" do
    field :parent_id, :id
    field :tenant_id, :id
    field :name, :string
    field :code, :string
    field :status, :string
    field :legal_name, :string
    field :registration_number, :string
    field :tax_id, :string
    field :legal_entity_type_id, :id
    field :jurisdiction, :string
    field :email, :string
    field :website, :string
    field :scope_activities, :map
    field :metadata, :map
    timestamps(type: :naive_datetime)
    field :deleted_at, :naive_datetime
  end
end
