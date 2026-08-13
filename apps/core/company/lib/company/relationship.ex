defmodule Bilimbi.Core.Company.Relationship do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}

  schema "company_relationships" do
    field :company_id, :id
    field :related_company_id, :id
    field :relationship_type_id, :id
    field :deleted_at, :naive_datetime
  end
end
