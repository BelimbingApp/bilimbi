defmodule Bilimbi.Base.Workflow.Subject do
  @moduledoc """
  Owner-proven workflow facts, returned by an installed subject adapter.

  `id` is the source bigint identity; `tenant_id` must match the supplied
  scope. `facts` contains only the plain data needed by owner hooks. No Ecto
  schema, queryable or caller-supplied authority crosses this boundary.
  """
  @enforce_keys [:id, :tenant_id, :status]
  defstruct [:id, :tenant_id, :company_id, :status, facts: %{}]

  @type t :: %__MODULE__{
          id: pos_integer(),
          tenant_id: pos_integer(),
          company_id: pos_integer() | nil,
          status: String.t(),
          facts: map()
        }
end
