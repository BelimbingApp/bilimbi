defmodule Bilimbi.Base.Grid.Source do
  @moduledoc """
  The one callback a module implements to put a table in the grid catalog.

  `query/1` returns the rows of that table the scope may read, as an Ecto
  queryable the grid will wrap in a subquery. The owner decides what "may
  read" means: the tenant filter (`Bilimbi.Base.Tenancy.scope_query/2`), the
  soft-delete filter, and any company boundary the owning module applies on
  its own list pages. The grid never adds a tenant predicate of its own,
  because only the owner knows where the tenant lives on its table, and it
  never reads a table whose owner did not declare it.

  The query must expose every declared field under the column named in the
  field declaration, either by selecting the schema struct (the default) or
  by selecting a map with those keys. A computed field is a map key the
  source selects; the grid does not know how it was computed.

  An edge function named by a link's `via` follows the same contract and
  selects `%{from_key: ..., to_key: ...}`: each row joins one row of the
  link's `from` table to one row of its `to` table. A `:one` link's edge
  must yield at most one `to_key` per `from_key`, or the joined rows multiply.
  """

  alias Bilimbi.Base.Tenancy.Scope

  @callback query(Scope.t()) :: Ecto.Queryable.t()
end
