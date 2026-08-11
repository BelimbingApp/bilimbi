defmodule Bilimbi.Base.Database.SchemaVerifier do
  @moduledoc """
  Compares PostgreSQL tables with an explicit compatibility contract.

  Verification is deliberately strict for tables owned by a contract: columns,
  indexes, and foreign keys must match exactly. Tables owned by other modules
  are ignored.
  """

  alias Ecto.Adapters.SQL

  @type default_spec ::
          nil
          | {:boolean, boolean()}
          | {:integer, integer()}
          | {:sequence, String.t()}
          | {:string, String.t()}

  @type column_spec :: %{
          required(:type) => atom() | {:varchar, pos_integer()} | {:timestamp, non_neg_integer()},
          required(:nullable) => boolean(),
          required(:default) => default_spec()
        }

  @type index_spec :: %{
          required(:columns) => [String.t()],
          required(:unique) => boolean(),
          required(:where) => String.t() | nil
        }

  @type foreign_key_spec :: %{
          required(:columns) => [String.t()],
          required(:references) => {String.t(), [String.t()]},
          required(:on_delete) => :cascade | :nilify_all | :nothing | :restrict
        }

  @type table_spec :: %{
          required(:name) => String.t(),
          required(:columns) => %{required(String.t()) => column_spec()},
          required(:indexes) => %{required(String.t()) => index_spec()},
          required(:foreign_keys) => %{required(String.t()) => foreign_key_spec()}
        }

  @spec verify(Ecto.Repo.t(), [table_spec()], keyword()) :: :ok | {:error, [String.t()]}
  def verify(repo, table_specs, opts \\ []) do
    schema = Keyword.get(opts, :prefix, "public")
    validate_identifier!(schema)

    errors =
      table_specs
      |> Enum.flat_map(&verify_table(repo, schema, &1))
      |> Enum.sort()

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp verify_table(repo, schema, spec) do
    case columns(repo, schema, spec.name) do
      [] ->
        ["missing table #{schema}.#{spec.name}"]

      actual_columns ->
        actual_indexes = indexes(repo, schema, spec.name)
        actual_foreign_keys = foreign_keys(repo, schema, spec.name)

        compare_columns(spec, actual_columns) ++
          compare_indexes(spec, actual_indexes) ++
          compare_foreign_keys(spec, actual_foreign_keys) ++
          compare_optional_groups(spec, actual_columns, actual_indexes, actual_foreign_keys)
    end
  end

  defp columns(repo, schema, table) do
    result =
      SQL.query!(
        repo,
        """
        SELECT column_name, data_type, character_maximum_length,
               datetime_precision, is_nullable, column_default
        FROM information_schema.columns
        WHERE table_schema = $1 AND table_name = $2
        ORDER BY ordinal_position
        """,
        [schema, table]
      )

    Map.new(result.rows, fn [name, type, length, precision, nullable, default] ->
      {name,
       %{
         type: type,
         length: length,
         precision: precision,
         nullable: nullable == "YES",
         default: default
       }}
    end)
  end

  defp indexes(repo, schema, table) do
    result =
      SQL.query!(
        repo,
        """
        SELECT index_class.relname,
               index_info.indisunique,
               array_agg(attribute.attname ORDER BY key_column.ordinality),
               pg_get_expr(index_info.indpred, index_info.indrelid)
        FROM pg_index AS index_info
        JOIN pg_class AS table_class ON table_class.oid = index_info.indrelid
        JOIN pg_namespace AS namespace ON namespace.oid = table_class.relnamespace
        JOIN pg_class AS index_class ON index_class.oid = index_info.indexrelid
        JOIN LATERAL unnest(index_info.indkey)
          WITH ORDINALITY AS key_column(attnum, ordinality) ON true
        JOIN pg_attribute AS attribute
          ON attribute.attrelid = table_class.oid
         AND attribute.attnum = key_column.attnum
        WHERE namespace.nspname = $1 AND table_class.relname = $2
        GROUP BY index_class.relname, index_info.indisunique,
                 index_info.indpred, index_info.indrelid
        ORDER BY index_class.relname
        """,
        [schema, table]
      )

    Map.new(result.rows, fn [name, unique, column_names, where] ->
      {name, %{unique: unique, columns: column_names, where: normalize_predicate(where)}}
    end)
  end

  defp foreign_keys(repo, schema, table) do
    result =
      SQL.query!(
        repo,
        """
        SELECT constraint_info.conname,
               array_agg(source_attribute.attname ORDER BY source_key.ordinality),
               target_table.relname,
               array_agg(target_attribute.attname ORDER BY source_key.ordinality),
               constraint_info.confdeltype::text
        FROM pg_constraint AS constraint_info
        JOIN pg_class AS source_table ON source_table.oid = constraint_info.conrelid
        JOIN pg_namespace AS namespace ON namespace.oid = source_table.relnamespace
        JOIN LATERAL unnest(constraint_info.conkey)
          WITH ORDINALITY AS source_key(attnum, ordinality) ON true
        JOIN LATERAL unnest(constraint_info.confkey)
          WITH ORDINALITY AS target_key(attnum, ordinality)
          ON target_key.ordinality = source_key.ordinality
        JOIN pg_attribute AS source_attribute
          ON source_attribute.attrelid = source_table.oid
         AND source_attribute.attnum = source_key.attnum
        JOIN pg_class AS target_table ON target_table.oid = constraint_info.confrelid
        JOIN pg_attribute AS target_attribute
          ON target_attribute.attrelid = target_table.oid
         AND target_attribute.attnum = target_key.attnum
        WHERE namespace.nspname = $1
          AND source_table.relname = $2
          AND constraint_info.contype = 'f'
        GROUP BY constraint_info.conname, target_table.relname,
                 constraint_info.confdeltype
        ORDER BY constraint_info.conname
        """,
        [schema, table]
      )

    Map.new(result.rows, fn [name, columns, target_table, target_columns, on_delete] ->
      {name,
       %{
         columns: columns,
         references: {target_table, target_columns},
         on_delete: decode_on_delete(on_delete)
       }}
    end)
  end

  defp compare_columns(spec, actual) do
    expected_names = spec.columns |> Map.keys() |> MapSet.new()
    optional = Map.get(spec, :optional_columns, %{})
    optional_names = optional |> Map.keys() |> MapSet.new()
    actual_names = actual |> Map.keys() |> MapSet.new()
    allowed_names = MapSet.union(expected_names, optional_names)

    missing =
      expected_names
      |> MapSet.difference(actual_names)
      |> Enum.map(&"#{spec.name}: missing column #{&1}")

    unexpected =
      actual_names
      |> MapSet.difference(allowed_names)
      |> Enum.map(&"#{spec.name}: unexpected column #{&1}")

    mismatched =
      allowed_names
      |> MapSet.intersection(actual_names)
      |> Enum.flat_map(fn name ->
        expected = Map.get(spec.columns, name) || Map.fetch!(optional, name)
        compare_column(spec.name, name, expected, actual[name])
      end)

    missing ++ unexpected ++ mismatched
  end

  defp compare_column(table, name, expected, actual) do
    []
    |> maybe_error(type_matches?(expected.type, actual), "#{table}.#{name}: incompatible type")
    |> maybe_error(
      expected.nullable == actual.nullable,
      "#{table}.#{name}: expected nullable=#{expected.nullable}, got #{actual.nullable}"
    )
    |> maybe_error(
      default_matches?(expected.default, actual.default),
      "#{table}.#{name}: incompatible default #{inspect(actual.default)}"
    )
  end

  defp compare_indexes(spec, actual) do
    compare_named_objects(
      spec.name,
      "index",
      spec.indexes,
      Map.get(spec, :optional_indexes, %{}),
      actual
    )
  end

  defp compare_foreign_keys(spec, actual) do
    compare_named_objects(
      spec.name,
      "foreign key",
      spec.foreign_keys,
      Map.get(spec, :optional_foreign_keys, %{}),
      actual
    )
  end

  defp compare_named_objects(table, kind, expected, optional, actual) do
    expected_names = expected |> Map.keys() |> MapSet.new()
    optional_names = optional |> Map.keys() |> MapSet.new()
    actual_names = actual |> Map.keys() |> MapSet.new()
    allowed_names = MapSet.union(expected_names, optional_names)

    missing =
      expected_names
      |> MapSet.difference(actual_names)
      |> Enum.map(&"#{table}: missing #{kind} #{&1}")

    unexpected =
      actual_names
      |> MapSet.difference(allowed_names)
      |> Enum.map(&"#{table}: unexpected #{kind} #{&1}")

    mismatched =
      allowed_names
      |> MapSet.intersection(actual_names)
      |> Enum.flat_map(fn name ->
        expected_object = Map.get(expected, name) || Map.fetch!(optional, name)

        if expected_object == actual[name],
          do: [],
          else: ["#{table}: incompatible #{kind} #{name}"]
      end)

    missing ++ unexpected ++ mismatched
  end

  defp compare_optional_groups(spec, columns, indexes, foreign_keys) do
    spec
    |> Map.get(:optional_groups, [])
    |> Enum.flat_map(fn group ->
      members =
        Enum.map(group.columns, &Map.has_key?(columns, &1)) ++
          Enum.map(group.indexes, &Map.has_key?(indexes, &1)) ++
          Enum.map(group.foreign_keys, &Map.has_key?(foreign_keys, &1))

      if Enum.any?(members) and not Enum.all?(members) do
        ["#{spec.name}: incomplete optional contribution #{group.name}"]
      else
        []
      end
    end)
  end

  defp type_matches?({:varchar, length}, actual) do
    actual.type == "character varying" and actual.length == length
  end

  defp type_matches?({:timestamp, precision}, actual) do
    actual.type == "timestamp without time zone" and actual.precision == precision
  end

  defp type_matches?(:bigint, actual), do: actual.type == "bigint"
  defp type_matches?(:boolean, actual), do: actual.type == "boolean"
  defp type_matches?(:date, actual), do: actual.type == "date"
  defp type_matches?(:json, actual), do: actual.type == "json"
  defp type_matches?(:text, actual), do: actual.type == "text"

  defp default_matches?(nil, nil), do: true

  defp default_matches?({:boolean, value}, actual),
    do: actual == to_string(value)

  defp default_matches?({:integer, value}, actual),
    do: actual in [Integer.to_string(value), "'#{value}'::bigint"]

  defp default_matches?({:sequence, sequence}, actual) when is_binary(actual),
    do: String.contains?(actual, sequence)

  defp default_matches?({:string, value}, actual) when is_binary(actual),
    do: String.starts_with?(actual, "'#{value}'")

  defp default_matches?(_expected, _actual), do: false

  defp maybe_error(errors, true, _message), do: errors
  defp maybe_error(errors, false, message), do: [message | errors]

  defp decode_on_delete("c"), do: :cascade
  defp decode_on_delete("a"), do: :nothing
  defp decode_on_delete("n"), do: :nilify_all
  defp decode_on_delete("r"), do: :restrict
  defp decode_on_delete(value), do: value

  defp normalize_predicate(nil), do: nil

  defp normalize_predicate(predicate) do
    predicate
    |> String.downcase()
    |> String.replace(~r/[\s()]+/, "")
  end

  defp validate_identifier!(identifier) do
    unless Regex.match?(~r/^[a-z_][a-z0-9_]*$/, identifier) do
      raise ArgumentError, "invalid PostgreSQL identifier: #{inspect(identifier)}"
    end
  end
end
