defmodule Bilimbi.Base.Integration.TestFixtures do
  @moduledoc false
  alias Bilimbi.Base.Database.TestTables
  alias Bilimbi.Base.Integration.SchemaContract
  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  # Owner-defined structure comes from the published contract, shared by all
  # module and consumer tests. No consumer restates integration DDL.
  def create_exchanges_table!(opts \\ []) do
    persistent = TestTables.persistent?(opts)
    [table] = SchemaContract.tables()
    columns = Map.merge(table.columns, table.optional_columns)

    definitions =
      Enum.map_join(columns, ", ", fn {name, spec} ->
        name <>
          " " <>
          sql_type(spec.type) <>
          if(spec.nullable, do: "", else: " NOT NULL") <>
          default(spec.default) <> if(name == "id", do: " PRIMARY KEY", else: "")
      end)

    SQL.query!(
      Repo,
      "#{TestTables.create(persistent)} #{table.name} (#{definitions}) #{TestTables.on_commit(persistent)}",
      []
    )
  end

  defp sql_type({:varchar, size}), do: "varchar(#{size})"
  defp sql_type({:timestamp, precision}), do: "timestamp(#{precision}) without time zone"
  defp sql_type(type), do: Atom.to_string(type)
  defp default(nil), do: ""
  defp default({:string, value}), do: " DEFAULT '#{value}'"
  defp default({:boolean, false}), do: " DEFAULT false"
  defp default({:integer, value}), do: " DEFAULT #{value}"
end
