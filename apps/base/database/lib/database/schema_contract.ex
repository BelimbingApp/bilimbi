defmodule Bilimbi.Base.Database.SchemaContract do
  @moduledoc """
  Contract implemented by modules that contribute compatible database schema.

  Structural table specifications are required. Data invariants are optional
  and remain owned by the module that understands their business meaning.
  """

  alias Bilimbi.Base.Database.SchemaVerifier

  @callback tables() :: [SchemaVerifier.table_spec()]
  @callback contributions() :: [SchemaVerifier.table_contribution_spec()]
  @callback verify_invariants(Ecto.Repo.t(), keyword()) :: :ok | {:error, [String.t()]}

  @doc """
  Columns holding credentials, tokens, or opaque session state that no read
  surface may expose, keyed by the owned table's name.

  The operator SQL console's role is granted every other column of such a
  table and never these, so `SELECT *` on it is refused and the console names
  the columns it may read. A table absent here is readable in full, and
  nothing detects an undeclared credential column, so declaring one belongs
  to the change that adds it. Keys are
  tables the module owns in the database, whether or not `tables/0` pins them
  as compatible baseline; a named column the table does not have fails
  reconciliation.
  """
  @callback secret_columns() :: %{String.t() => [String.t(), ...]}

  @optional_callbacks contributions: 0, verify_invariants: 2, secret_columns: 0
end
