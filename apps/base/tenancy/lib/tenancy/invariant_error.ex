defmodule Bilimbi.Base.Tenancy.InvariantError do
  @moduledoc """
  Raised when persisted tenant identity contradicts Base Tenancy invariants.
  """

  defexception message: "tenant identity invariant violated", details: %{}
end
