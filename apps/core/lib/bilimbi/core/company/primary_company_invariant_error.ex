defmodule Bilimbi.Core.Company.PrimaryCompanyInvariantError do
  @moduledoc """
  Raised when a primary-company assignment contradicts Core Company invariants.
  """

  defexception message: "primary-company invariant violated", details: %{}
end
