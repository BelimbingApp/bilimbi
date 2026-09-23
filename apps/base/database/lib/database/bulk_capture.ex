defmodule Bilimbi.Base.Database.BulkCapture do
  @moduledoc """
  Gathers the rows a query-based bulk write affected, so `insert_all`,
  `update_all` and `delete_all` reach the same capture seam struct writes
  use (ADR 0013).

  A bulk write hands the repo a query, not a changeset, so the rows have
  to be read. What that costs differs by operation, and this module pays
  only what each one needs:

    * `insert_all` — `RETURNING` is the new row. Nothing else is read.
    * `delete_all` — `RETURNING` **is** the old row. Nothing else is read.
    * `update_all` — `RETURNING` is the new row, so the originals take one
      additional `SELECT` before the statement runs.

  Nothing is read for a schema the capture module excludes: `plan_*/2`
  asks `WriteCapture.bulk_captured?/1` first and returns `:skip`, which
  leaves the caller's statement untouched.

  ## The caller's result is preserved exactly

  Gathering rows means asking for them, which changes what the statement
  returns. Every caller in the product reads `{count, nil}` from a
  select-less `delete_all`, so `caller_result/2` hands back what the
  caller would have received had capture not been configured — the added
  `select` and `returning: true` are invisible above this module. A query
  that already carries a `select` is not rewritten at all; its rows are
  read separately instead.

  ## Upserts

  `insert_all` with a replacing `:on_conflict` cannot be told apart from a
  plain insert by its result — the row comes back either way. When the
  conflict target names fields, the rows it could collide with are read
  first, and a returned row already in that set is recorded as the update
  it was. When it does not (an `:unsafe_fragment` index predicate), the
  write is **not** captured: a record that called a replacement a creation
  would be a false one, and a missing record is the lesser failure. That
  case is logged and counted on the capture-failure telemetry event rather
  than passing silently.

  ## Capture never fails the write

  A pre-read that raises, a post-read that raises, a schema whose rows
  cannot be gathered — all of it is rescued here and downgraded to "no
  capture", exactly as ADR 0013 requires of the seam itself.
  """

  import Ecto.Query

  alias Bilimbi.Base.Database.WriteCapture

  @enforce_keys [:schema, :mode]
  defstruct [:schema, :mode, :queryable, :old_rows, :returning, existing: %{}, read_opts: []]

  @typedoc """
  How the affected rows are obtained.

    * `:returning` — the statement itself is rewritten to return them;
    * `:pre_read` — they were read before the statement, which runs as the
      caller wrote it;
    * `:post_read` — the originals were read before and the results are
      read back afterwards, for a caller whose query carries its own
      `select`.
  """
  @type mode :: :returning | :pre_read | :post_read

  @type t :: %__MODULE__{
          schema: module(),
          mode: mode(),
          queryable: Ecto.Queryable.t() | nil,
          old_rows: [Ecto.Schema.t()] | nil,
          returning: term(),
          existing: %{optional(term()) => Ecto.Schema.t()},
          read_opts: keyword()
        }

  @doc """
  Plans capture for `insert_all`, or `:skip` to leave the write alone.
  """
  @spec plan_insert(module(), term(), term(), keyword()) :: t() | :skip
  def plan_insert(repo, schema_or_source, entries, opts) do
    schema = schema(schema_or_source)

    if entries != [] and WriteCapture.bulk_captured?(schema) and primary_key(schema) do
      case conflicting_rows(repo, schema, entries, opts) do
        :unclassifiable ->
          unclassifiable_upsert(schema)

        existing ->
          %__MODULE__{
            schema: schema,
            mode: :returning,
            existing: existing,
            returning: Keyword.get(opts, :returning)
          }
      end
    else
      :skip
    end
  rescue
    error -> skip_after(:insert, schema(schema_or_source), error, __STACKTRACE__)
  end

  @doc """
  Plans capture for `update_all`, reading the originals, or `:skip`.
  """
  @spec plan_update(module(), Ecto.Queryable.t(), keyword()) :: t() | :skip
  def plan_update(repo, queryable, opts) do
    query = Ecto.Queryable.to_query(queryable)
    schema = schema(query)
    read_opts = read_opts(opts)

    with true <- WriteCapture.bulk_captured?(schema) and not is_nil(primary_key(schema)),
         [_ | _] = old_rows <- repo.all(full_row_query(query), read_opts) do
      if is_nil(query.select) do
        %__MODULE__{
          schema: schema,
          mode: :returning,
          queryable: full_row_query(query),
          old_rows: old_rows,
          read_opts: read_opts
        }
      else
        %__MODULE__{
          schema: schema,
          mode: :post_read,
          queryable: query,
          old_rows: old_rows,
          read_opts: read_opts
        }
      end
    else
      _nothing_to_capture -> :skip
    end
  rescue
    error -> skip_after(:update, schema(queryable), error, __STACKTRACE__)
  end

  @doc """
  Plans capture for `delete_all`, whose returned rows are the old ones, or
  `:skip`.
  """
  @spec plan_delete(module(), Ecto.Queryable.t(), keyword()) :: t() | :skip
  def plan_delete(repo, queryable, opts) do
    query = Ecto.Queryable.to_query(queryable)
    schema = schema(query)

    cond do
      not WriteCapture.bulk_captured?(schema) or is_nil(primary_key(schema)) ->
        :skip

      is_nil(query.select) ->
        %__MODULE__{schema: schema, mode: :returning, queryable: full_row_query(query)}

      true ->
        case repo.all(full_row_query(query), read_opts(opts)) do
          [] -> :skip
          rows -> %__MODULE__{schema: schema, mode: :pre_read, queryable: query, old_rows: rows}
        end
    end
  rescue
    error -> skip_after(:delete, schema(queryable), error, __STACKTRACE__)
  end

  @doc "The queryable the repo should hand `super`."
  @spec write_queryable(t()) :: Ecto.Queryable.t()
  def write_queryable(%__MODULE__{queryable: queryable}), do: queryable

  @doc "The options the repo should hand `super`."
  @spec write_opts(t(), keyword()) :: keyword()
  def write_opts(%__MODULE__{}, opts), do: Keyword.put(opts, :returning, true)

  @doc """
  Dispatches the affected rows to the capture seam.

  Named for what it does to the audit trail, not to the database: the
  business write has already happened by the time this runs.
  """
  @spec record(module(), :insert | :update | :delete, t(), term()) :: :ok
  def record(repo, action, %__MODULE__{} = plan, result) do
    plan.schema
    |> WriteCapture.dispatch_bulk(changes(repo, action, plan, result))
  rescue
    error -> WriteCapture.capture_failed(action, plan.schema, error, __STACKTRACE__)
  end

  @doc """
  The result the caller would have received had capture not been
  configured.
  """
  @spec caller_result(t(), term()) :: term()
  def caller_result(%__MODULE__{mode: mode}, result) when mode in [:pre_read, :post_read],
    do: result

  def caller_result(%__MODULE__{schema: schema, returning: returning}, {count, rows}),
    do: {count, returned_rows(schema, returning, rows)}

  # Nothing asked for: `{count, nil}`, the shape every select-less caller
  # in the product matches on.
  defp returned_rows(_schema, returning, _rows) when returning in [nil, false], do: nil
  defp returned_rows(_schema, true, rows), do: rows

  # A field list: the caller gets structs carrying those fields and no
  # others, which is what Ecto would have loaded for them.
  defp returned_rows(schema, fields, rows) when is_list(fields) do
    blank = struct(schema)

    Enum.map(rows, fn row ->
      Enum.reduce([:__meta__ | fields], blank, &Map.put(&2, &1, Map.get(row, &1)))
    end)
  end

  defp returned_rows(_schema, _returning, rows), do: rows

  defp changes(_repo, :insert, %__MODULE__{schema: schema, existing: existing}, {_count, rows}) do
    key = primary_key(schema)

    Enum.map(rows || [], fn row ->
      case Map.fetch(existing, Map.get(row, key)) do
        {:ok, previous} -> {:update, previous, row}
        :error -> {:insert, nil, row}
      end
    end)
  end

  defp changes(_repo, :delete, %__MODULE__{mode: :returning}, {_count, rows}),
    do: Enum.map(rows || [], &{:delete, &1, nil})

  defp changes(_repo, :delete, %__MODULE__{old_rows: old_rows}, _result),
    do: Enum.map(old_rows, &{:delete, &1, nil})

  defp changes(_repo, :update, %__MODULE__{mode: :returning} = plan, {_count, rows}),
    do: paired(primary_key(plan.schema), plan.old_rows, rows || [])

  defp changes(repo, :update, %__MODULE__{mode: :post_read} = plan, _result) do
    key = primary_key(plan.schema)
    ids = Enum.map(plan.old_rows, &Map.get(&1, key))

    paired(
      key,
      plan.old_rows,
      repo.all(from(row in plan.schema, where: field(row, ^key) in ^ids), plan.read_opts)
    )
  end

  # A row the pre-read did not see was written between the two statements;
  # it is recorded as a change with no known original rather than as a
  # diff that would invent one.
  defp paired(key, old_rows, new_rows) do
    originals = Map.new(old_rows, &{Map.get(&1, key), &1})

    Enum.map(new_rows, fn row -> {:update, Map.get(originals, Map.get(row, key)), row} end)
  end

  # `:raise` and `:nothing` need no pre-read: the first inserts or fails,
  # and the second returns only the rows it genuinely inserted.
  defp conflicting_rows(repo, schema, entries, opts) do
    case Keyword.get(opts, :on_conflict, :raise) do
      conflict when conflict in [:raise, :nothing] ->
        %{}

      _replacing ->
        with fields when is_list(fields) <- Keyword.get(opts, :conflict_target),
             true <- Enum.all?(fields, &is_atom/1) and fields != [],
             entries when is_list(entries) <- entries,
             {:ok, filter} <- conflict_filter(fields, entries) do
          key = primary_key(schema)

          from(row in schema, where: ^filter)
          |> repo.all(read_opts(opts))
          |> Map.new(&{Map.get(&1, key), &1})
        else
          _no_usable_target -> :unclassifiable
        end
    end
  end

  # One `IN` per conflict field rather than an `OR` per entry: it stays one
  # small statement for a large batch, and over-selecting is harmless —
  # a row the insert creates cannot already be in the set.
  defp conflict_filter(fields, entries) do
    Enum.reduce_while(fields, {:ok, true}, fn field, {:ok, filter} ->
      values = Enum.map(entries, &entry_value(&1, field))

      if Enum.any?(values, &is_nil/1) do
        {:halt, :no_usable_target}
      else
        {:cont, {:ok, dynamic([row], ^filter and field(row, ^field) in ^Enum.uniq(values))}}
      end
    end)
  end

  # The pre-reads run against the same schema prefix, timeout and log
  # settings the caller's write does; a prefixed write read from the
  # default prefix would record another schema's rows.
  defp read_opts(opts), do: Keyword.take(opts, [:prefix, :timeout, :log])

  defp entry_value(entry, field) when is_map(entry), do: Map.get(entry, field)
  defp entry_value(entry, field) when is_list(entry), do: Keyword.get(entry, field)
  defp entry_value(_entry, _field), do: nil

  defp full_row_query(%Ecto.Query{} = query),
    do: query |> exclude(:select) |> select([row], row)

  defp schema(%Ecto.Query{from: %{source: {_table, schema}}}) when is_atom(schema), do: schema
  defp schema({_source, schema}) when is_atom(schema), do: schema
  defp schema(schema) when is_atom(schema), do: schema
  defp schema(queryable) when is_struct(queryable), do: schema(Ecto.Queryable.to_query(queryable))
  defp schema(_other), do: nil

  defp primary_key(schema) when is_atom(schema) and not is_nil(schema) do
    if Code.ensure_loaded?(schema) and function_exported?(schema, :__schema__, 1) do
      case schema.__schema__(:primary_key) do
        [key] -> key
        _composite_or_none -> nil
      end
    end
  end

  defp primary_key(_other), do: nil

  defp unclassifiable_upsert(schema) do
    WriteCapture.capture_failed(
      :insert,
      schema,
      %ArgumentError{
        message:
          "a replacing upsert whose conflict target is not a field list cannot be " <>
            "told from an insert, so it was not captured; wrap the caller in " <>
            "Bilimbi.Base.Audit.without_auditing/1 if that is intended"
      },
      []
    )

    :skip
  end

  defp skip_after(action, schema, error, stacktrace) do
    WriteCapture.capture_failed(action, schema, error, stacktrace)
    :skip
  end
end
