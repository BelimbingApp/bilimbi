defmodule Bilimbi.Core.Employee.TypeSummary do
  @moduledoc "Public read model for an employee type."

  alias Bilimbi.Core.Employee.EmployeeType

  @fields [:id, :code, :label, :is_system, :company_id]

  @enforce_keys [:id, :code, :label, :is_system]
  defstruct @fields

  @type t :: %__MODULE__{
          id: pos_integer(),
          code: String.t(),
          label: String.t(),
          is_system: boolean(),
          company_id: pos_integer() | nil
        }

  @spec from_schema(EmployeeType.t()) :: t()
  def from_schema(employee_type) do
    struct!(__MODULE__, Map.from_struct(employee_type) |> Map.take(@fields))
  end
end
