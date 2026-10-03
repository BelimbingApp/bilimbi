defmodule Bilimbi.Base.Workflow.Subject do
  @moduledoc """
  Owner-proven workflow facts, returned by an installed subject adapter.

  `id` is the source bigint identity; `tenant_id` must match the supplied
  scope. `facts` contains only the plain data needed by owner hooks. No Ecto
  schema, queryable or caller-supplied authority crosses this boundary.

  `version` is the owner's opaque token for the row as loaded, such as a
  digest of its columns. A page shows it with the available human actions
  and echoes it back as `expected_subject_version`; the gate refuses an
  action whose subject changed since. Belimbing hashed every raw attribute,
  so a token covering less than the row lets a stale page act. Owners that
  contribute no human actions may leave it `nil`.
  """
  @enforce_keys [:id, :tenant_id, :status]
  defstruct [:id, :tenant_id, :company_id, :status, :version, facts: %{}]

  @type t :: %__MODULE__{
          id: pos_integer(),
          tenant_id: pos_integer(),
          company_id: pos_integer() | nil,
          status: String.t(),
          version: String.t() | nil,
          facts: map()
        }
end
