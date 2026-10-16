defmodule Bilimbi.Core.Employee.HrHandoffEntry do
  @moduledoc """
  One retained legacy HR row, as `Bilimbi.Core.Employee.hr_handoff_page/3`
  hands it to the owner of employment facts.

  It carries the HR facts and metadata verbatim, the row's own clocks and
  the Core Person mapping. `person_id` and `affiliation_id` are `nil` while
  the row has no mapping; `company_id` is the employer of the legacy row.
  Identity and contact facts stay with Core Person and are not copied here.
  """

  alias Bilimbi.Core.Employee.Schema

  @enforce_keys [:employee_id, :company_id, :employee_number, :employee_type, :status]
  defstruct [
    :employee_id,
    :company_id,
    :employee_number,
    :employee_type,
    :status,
    :employment_start,
    :employment_end,
    :metadata,
    :created_at,
    :updated_at,
    :person_id,
    :affiliation_id
  ]

  @type t :: %__MODULE__{
          employee_id: pos_integer(),
          company_id: pos_integer(),
          employee_number: String.t(),
          employee_type: String.t(),
          status: String.t(),
          employment_start: Date.t() | nil,
          employment_end: Date.t() | nil,
          metadata: map() | list() | nil,
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil,
          person_id: pos_integer() | nil,
          affiliation_id: pos_integer() | nil
        }

  @doc false
  @spec from_schema(Schema.t(), %{person_id: pos_integer(), affiliation_id: pos_integer()} | nil) ::
          t()
  def from_schema(%Schema{} = employee, mapping) do
    %__MODULE__{
      employee_id: employee.id,
      company_id: employee.company_id,
      employee_number: employee.employee_number,
      employee_type: employee.employee_type,
      status: employee.status,
      employment_start: employee.employment_start,
      employment_end: employee.employment_end,
      metadata: employee.metadata,
      created_at: employee.created_at,
      updated_at: employee.updated_at,
      person_id: mapping && mapping.person_id,
      affiliation_id: mapping && mapping.affiliation_id
    }
  end
end
