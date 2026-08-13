defmodule Bilimbi.Core.Employee.AdministrationEntry do
  @moduledoc """
  UI-safe Employee facts for an administration index row.

  This deliberately excludes relationship records, metadata, and persistence
  details. Consumers needing an Employee detail record must use the separate
  public detail API instead of making this list row wider by accident.
  """

  alias Bilimbi.Core.Employee.Schema

  @enforce_keys [:id, :employee_number, :full_name, :employee_type, :status]
  defstruct [
    :id,
    :employee_number,
    :full_name,
    :short_name,
    :designation,
    :employee_type,
    :employee_type_label,
    :email,
    :status
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          employee_number: String.t(),
          full_name: String.t(),
          short_name: String.t() | nil,
          designation: String.t() | nil,
          employee_type: String.t(),
          employee_type_label: String.t() | nil,
          email: String.t() | nil,
          status: String.t()
        }

  @spec from_schema(Schema.t()) :: t()
  def from_schema(%Schema{} = employee) do
    from_query_result({employee, nil})
  end

  @spec from_query_result({Schema.t(), String.t() | nil}) :: t()
  def from_query_result({%Schema{} = employee, employee_type_label}) do
    %__MODULE__{
      id: employee.id,
      employee_number: employee.employee_number,
      full_name: employee.full_name,
      short_name: employee.short_name,
      designation: employee.designation,
      employee_type: employee.employee_type,
      employee_type_label: employee_type_label || fallback_type_label(employee.employee_type),
      email: employee.email,
      status: employee.status
    }
  end

  defp fallback_type_label(employee_type) do
    employee_type
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
