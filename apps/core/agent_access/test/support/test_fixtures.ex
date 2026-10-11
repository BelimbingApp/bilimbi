defmodule Bilimbi.Core.AgentAccess.TestFixtures do
  @moduledoc false
  alias Bilimbi.Base.Database.TestTables
  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.AgentAccess.SchemaContract
  alias Ecto.Adapters.SQL
  # Owner-defined test structure comes from the new storage contract.
  def create_tables!(opts \\ []) do
    persistent = TestTables.persistent?(opts)

    for table <- SchemaContract.storage_tables() do
      columns =
        Enum.map_join(table.columns, ", ", fn
          {"id", _} ->
            "id bigserial PRIMARY KEY"

          {name, spec} ->
            name <>
              " " <>
              type(spec.type) <>
              if(spec.nullable, do: "", else: " NOT NULL") <> default(spec.default)
        end)

      fks =
        Enum.map_join(table.foreign_keys, "", fn {name, spec} ->
          {target, [column]} = spec.references

          ", CONSTRAINT #{name} FOREIGN KEY (#{Enum.join(spec.columns, ",")}) REFERENCES #{target}(#{column}) ON DELETE #{deletion(spec.on_delete)}"
        end)

      SQL.query!(
        Repo,
        "#{TestTables.create(persistent)} #{table.name} (#{columns}#{fks}) #{TestTables.on_commit(persistent)}",
        []
      )

      for {name, index} <- table.indexes, name != table.name <> "_pkey" do
        SQL.query!(
          Repo,
          "CREATE #{if index.unique, do: "UNIQUE ", else: ""}INDEX #{name} ON #{table.name}(#{Enum.join(index.columns, ",")})",
          []
        )
      end
    end
  end

  defp deletion(:restrict), do: "RESTRICT"
  defp deletion(:cascade), do: "CASCADE"
  defp deletion(:nilify_all), do: "SET NULL"
  defp type({:varchar, size}), do: "varchar(#{size})"
  defp type({:timestamp, precision}), do: "timestamp(#{precision}) without time zone"
  defp type(value), do: Atom.to_string(value)
  defp default(nil), do: ""
  defp default({:string, value}), do: " DEFAULT '#{value}'"
end
