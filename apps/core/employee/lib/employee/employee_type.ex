defmodule Bilimbi.Core.Employee.EmployeeType do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "employee_types" do
    field :code, :string
    field :label, :string
    field :is_system, :boolean, default: false
    field :company_id, :id
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @spec custom_changeset(pos_integer(), map()) :: Ecto.Changeset.t()
  def custom_changeset(company_id, attributes) do
    %__MODULE__{}
    |> cast(attributes, [:code, :label])
    |> put_change(:company_id, company_id)
    |> put_change(:is_system, false)
    |> update_change(:code, &(&1 |> String.trim() |> String.downcase()))
    |> update_change(:label, &String.trim/1)
    |> validate_required([:code, :label, :company_id])
    |> validate_format(:code, ~r/^[a-z][a-z0-9_]*$/)
    |> validate_length(:code, max: 255)
    |> validate_length(:label, min: 1, max: 255)
    |> unique_constraint(:code, name: :employee_types_code_unique)
  end
end
