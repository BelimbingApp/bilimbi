defmodule Bilimbi.Core.Employee.Summary do
  @moduledoc "Public read model for an employment record."

  alias Bilimbi.Core.Employee.Schema

  @fields [
    :id,
    :company_id,
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
    :metadata,
    :created_at,
    :updated_at
  ]

  @enforce_keys [:id, :company_id, :employee_number, :full_name, :employee_type, :status]
  defstruct @fields

  @type t :: %__MODULE__{
          id: pos_integer(),
          company_id: pos_integer(),
          department_id: pos_integer() | nil,
          supervisor_id: pos_integer() | nil,
          employee_number: String.t(),
          full_name: String.t(),
          short_name: String.t() | nil,
          designation: String.t() | nil,
          employee_type: String.t(),
          job_description: String.t() | nil,
          email: String.t() | nil,
          mobile_number: String.t() | nil,
          status: String.t(),
          employment_start: Date.t() | nil,
          employment_end: Date.t() | nil,
          metadata: term(),
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @spec from_schema(Schema.t()) :: t()
  def from_schema(employee) do
    struct!(__MODULE__, Map.from_struct(employee) |> Map.take(@fields))
  end

  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{short_name: short_name, full_name: full_name}) do
    short_name || full_name
  end
end
