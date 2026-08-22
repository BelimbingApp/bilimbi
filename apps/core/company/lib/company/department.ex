defmodule Bilimbi.Core.Company.Department do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @statuses ~w(active inactive suspended)

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          company_id: pos_integer() | nil,
          department_type_id: pos_integer() | nil,
          head_id: pos_integer() | nil,
          status: String.t(),
          metadata: map() | nil,
          company: Bilimbi.Core.Company.Schema.t() | Ecto.Association.NotLoaded.t() | nil,
          type: Bilimbi.Core.Company.DepartmentType.t() | Ecto.Association.NotLoaded.t() | nil,
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "company_departments" do
    field :head_id, :id
    field :status, :string, default: "active"
    field :metadata, Bilimbi.Base.Database.Json

    belongs_to :company, Bilimbi.Core.Company.Schema, foreign_key: :company_id
    belongs_to :type, Bilimbi.Core.Company.DepartmentType, foreign_key: :department_type_id

    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  def statuses, do: @statuses

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(department, attrs) do
    department
    |> cast(attrs, [:company_id, :department_type_id, :head_id, :status, :metadata])
    |> validate_required([:company_id, :department_type_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:company_id, :department_type_id],
      name: :company_departments_company_id_department_type_id_unique
    )
    |> foreign_key_constraint(:company_id, name: :company_departments_company_id_foreign)
    |> foreign_key_constraint(:department_type_id,
      name: :company_departments_department_type_id_foreign
    )
  end

  @spec status_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def status_changeset(department, status) do
    department
    |> change(%{status: status})
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Appoints (or clears, with `nil`) the department head. The head is an employee;
  the foreign-key constraint nilifies the head if that employee is removed.
  """
  @spec head_changeset(t(), pos_integer() | nil) :: Ecto.Changeset.t()
  def head_changeset(department, head_id) do
    department
    |> cast(%{"head_id" => head_id}, [:head_id])
    |> foreign_key_constraint(:head_id, name: :company_departments_head_id_foreign)
  end
end
