defmodule Bilimbi.Core.Employee.AffiliationProof do
  @moduledoc """
  Schema-free proof of one employee's company affiliation.

  Values are created only by `Bilimbi.Core.Employee.lock_affiliation/3` and are
  valid only while that caller's shared Repo transaction remains open.
  """

  @enforce_keys [:id, :company_id]
  defstruct [:id, :company_id]

  @type t :: %__MODULE__{
          id: pos_integer(),
          company_id: pos_integer()
        }

  @doc false
  @spec from_ids(pos_integer(), pos_integer()) :: t()
  def from_ids(id, company_id)
      when is_integer(id) and id > 0 and is_integer(company_id) and company_id > 0 do
    %__MODULE__{id: id, company_id: company_id}
  end
end
