defmodule Bilimbi.Core.Employee.TypeAdministrationEntry do
  @moduledoc """
  UI-safe Employee Type facts for an administration index row.

  This deliberately excludes schema relationships, metadata, and persistence
  details.
  """

  alias Bilimbi.Core.Employee.EmployeeType

  @enforce_keys [:id, :code, :label, :is_system, :employees_count]
  defstruct [:id, :code, :label, :is_system, :company_id, :employees_count]

  @type t :: %__MODULE__{
          id: pos_integer(),
          code: String.t(),
          label: String.t(),
          is_system: boolean(),
          company_id: pos_integer() | nil,
          employees_count: non_neg_integer()
        }

  @spec from_query_result({EmployeeType.t(), non_neg_integer()}) :: t()
  def from_query_result({%EmployeeType{} = type, employees_count}) do
    %__MODULE__{
      id: type.id,
      code: type.code,
      label: type.label,
      is_system: type.is_system,
      company_id: type.company_id,
      employees_count: employees_count
    }
  end
end
