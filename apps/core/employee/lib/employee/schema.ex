defmodule Bilimbi.Core.Employee.Schema do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @fields [
    :department_id,
    :supervisor_id,
    :employee_number,
    :full_name,
    :short_name,
    :designation,
    :employee_type,
    :job_description,
    :email,
    :mobile_number,
    :status,
    :employment_start,
    :employment_end,
    :metadata
  ]
  @statuses ~w(pending probation active inactive terminated)

  schema "employees" do
    field :company_id, :id
    field :department_id, :id
    field :supervisor_id, :id
    field :employee_number, :string
    field :full_name, :string
    field :short_name, :string
    field :designation, :string
    field :employee_type, :string
    field :job_description, :string
    field :email, :string
    field :mobile_number, :string
    field :status, :string
    field :employment_start, :date
    field :employment_end, :date
    field :metadata, Bilimbi.Base.Database.Json
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @spec creation_changeset(pos_integer(), map()) :: Ecto.Changeset.t()
  def creation_changeset(company_id, attributes) do
    %__MODULE__{employee_type: "full_time", status: "active"}
    |> cast(attributes, @fields)
    |> put_change(:company_id, company_id)
    |> common_validations()
  end

  @spec update_changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def update_changeset(employee, attributes) do
    employee
    |> cast(attributes, @fields)
    |> common_validations()
  end

  defp common_validations(changeset) do
    changeset
    |> trim_changes([:employee_number, :full_name, :short_name, :designation, :email])
    |> validate_required([:company_id, :employee_number, :full_name, :employee_type, :status])
    |> validate_length(:employee_number, min: 1, max: 255)
    |> validate_length(:full_name, min: 1, max: 255)
    |> validate_length(:employee_type, min: 1, max: 255)
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/, message: "has invalid format")
    |> validate_employment_period()
    |> unique_constraint(:employee_number, name: :employees_company_id_employee_number_unique)
    |> foreign_key_constraint(:company_id, name: :employees_company_id_foreign)
    |> foreign_key_constraint(:department_id, name: :employees_department_id_foreign)
    |> foreign_key_constraint(:supervisor_id, name: :employees_supervisor_id_foreign)
  end

  defp trim_changes(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, result ->
      update_change(result, field, &String.trim/1)
    end)
  end

  defp validate_employment_period(changeset) do
    start_date = get_field(changeset, :employment_start)
    end_date = get_field(changeset, :employment_end)

    if start_date && end_date && Date.before?(end_date, start_date) do
      add_error(changeset, :employment_end, "must be on or after employment start")
    else
      changeset
    end
  end
end
