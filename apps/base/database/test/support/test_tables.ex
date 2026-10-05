defmodule Bilimbi.Base.Database.TestTables do
  @moduledoc """
  How an owner's test fixture builds a table that a `LockSchema` test can use.

  The sandbox gives every test temporary tables, which one connection cannot
  share. A fixture that takes `persistent: true` creates the same table as a
  real one in the current schema instead, so a lock test builds its schema
  from the owner's DDL rather than restating it:

      def create_tenants_table!(opts \\\\ []) do
        persistent = TestTables.persistent?(opts)

        SQL.query!(Repo, "\#{TestTables.create(persistent)} tenants (...) \#{TestTables.on_commit(persistent)}", [])
      end
  """

  @doc "Whether the fixture was asked for a real (cross-connection) table."
  def persistent?(opts) when is_list(opts), do: Keyword.get(opts, :persistent, false)

  @doc "The `CREATE` prefix for a table in the sandbox (temporary) or in a schema."
  def create(true), do: "CREATE TABLE"
  def create(false), do: "CREATE TEMPORARY TABLE"

  @doc "The `ON COMMIT` suffix (`PRESERVE ROWS` or `DROP`) a temporary table needs and a real table must not carry."
  def on_commit(persistent, mode \\ "PRESERVE ROWS")
  def on_commit(true, _mode), do: ""
  def on_commit(false, mode), do: "ON COMMIT #{mode}"
end
