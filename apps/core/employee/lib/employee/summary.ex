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
    :employee_type_label,
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
          employee_type_label: String.t() | nil,
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

  @doc """
  Builds a summary from an `{employee, employee_type_label}` query result, so
  reads that join the type table (e.g. `list_employees/2`) carry the same
  humanized label the index shows. Mirrors `AdministrationEntry.from_query_result/1`.
  """
  @spec from_query_result({Schema.t(), String.t() | nil}) :: t()
  def from_query_result({%Schema{} = employee, employee_type_label}) do
    %{
      from_schema(employee)
      | employee_type_label: employee_type_label || fallback_type_label(employee.employee_type)
    }
  end

  # The type row is usually present (system types are seeded), but a code with
  # no matching row still reads as a label rather than a raw enum.
  defp fallback_type_label(employee_type) do
    employee_type
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{short_name: short_name, full_name: full_name}) do
    short_name || full_name
  end
end
