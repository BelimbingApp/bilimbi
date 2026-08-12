defmodule Bilimbi.Core.Company.Department do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}

  schema "company_departments" do
    field(:company_id, :id)
    field(:department_type_id, :id)
    field(:head_id, :id)
    field(:status, :string)
    field(:metadata, Bilimbi.Base.Database.Json)
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end
end
