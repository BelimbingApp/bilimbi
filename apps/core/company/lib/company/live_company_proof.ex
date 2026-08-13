defmodule Bilimbi.Core.Company.LiveCompanyProof do
  @moduledoc """
  Schema-free proof that a live Company row is locked by the current transaction.

  This value carries only the Company identity sibling workflows need. It is not
  an Ecto schema or queryable, and it is valid only while the shared Repo
  transaction that returned it remains open.
  """

  @enforce_keys [:id]
  defstruct [:id]

  @type t :: %__MODULE__{id: pos_integer()}

  @doc false
  @spec from_id(pos_integer()) :: t()
  def from_id(id) when is_integer(id) and id > 0, do: %__MODULE__{id: id}
end
