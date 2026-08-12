defmodule Bilimbi.Base.Database do
  @moduledoc """
  Owns Bilimbi's shared Ecto repository and database compatibility utilities.

  Business modules depend on this lower-level Base module instead of depending
  on the Base composition application, keeping the dependency graph acyclic.
  """
end
