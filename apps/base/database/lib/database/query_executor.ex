defmodule Bilimbi.Base.Database.QueryExecutor do
  @moduledoc """
  Safe, read-only SQL query execution engine.

  Enforces read-only transactions, query timeouts, row limits, keyword checks,
  and parameter extraction for user-defined SQL queries.
  """

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  @max_rows 1000
  @default_timeout_ms 10_000

  @forbidden_keywords ~w(
    INSERT
    UPDATE
    DELETE
    DROP
    ALTER
    CREATE
    TRUNCATE
    REPLACE
    GRANT
    REVOKE
    LOCK
    UNLOCK
  )

  @type result :: %{
          columns: [String.t()],
          rows: [map()],
          total: non_neg_integer(),
          page: pos_integer(),
          per_page: pos_integer(),
          last_page: pos_integer()
        }

  @doc """
  Executes a read-only SQL query with pagination, sorting, and parameter binding.
  """
  @spec execute_readonly(String.t(), map() | list(), keyword()) ::
          {:ok, result()} | {:error, String.t()}
  def execute_readonly(sql, params \\ %{}, opts \\ [])
      when is_binary(sql) and (is_map(params) or is_list(params)) and is_list(opts) do
    trimmed_sql = sql |> String.trim() |> String.trim_trailing(";") |> String.trim()

    with :ok <- require_operator(opts),
         :ok <- validate_sql(trimmed_sql) do
      page = max(Keyword.get(opts, :page, 1), 1)
      per_page = min(max(Keyword.get(opts, :per_page, 25), 1), @max_rows)
      order_by = Keyword.get(opts, :order_by)
      order_dir = Keyword.get(opts, :order_dir, :asc)
      timeout_ms = Keyword.get(opts, :timeout, @default_timeout_ms)

      {bound_sql, bound_params} = bind_parameters(trimmed_sql, params)

      execute_in_readonly_transaction(
        bound_sql,
        bound_params,
        page,
        per_page,
        order_by,
        order_dir,
        timeout_ms
      )
    end
  end

  # #650: the raw-SQL console is operator tooling and carries no tenant predicate,
  # so the caller must assert the platform-operator tenant via `operator: true`.
  # Absent or false fails closed, so no future caller reaches this API
  # tenant-scoped by accident.
  defp require_operator(opts) do
    if Keyword.get(opts, :operator) == true,
      do: :ok,
      else: {:error, "The database console is restricted to the platform operator."}
  end

  @doc """
  Extracts named parameter tokens (e.g., `:status`, `:company_id`) from SQL query text,
  ignoring string literals and PostgreSQL type casts (`::type`).
  """
  @spec extract_named_parameters(String.t()) :: [String.t()]
  def extract_named_parameters(sql) when is_binary(sql) do
    # Remove single-quoted string literals
    sanitized = Regex.replace(~r/'(?:''|[^'])*'/, sql, "")
    # Remove block comments
    sanitized = Regex.replace(~r/\/\*.*?\*\//s, sanitized, "")
    # Remove line comments
    sanitized = Regex.replace(~r/--.*$/m, sanitized, "")
    # Remove double colons used in type casts (e.g. ::int)
    sanitized = Regex.replace(~r/::[a-zA-Z_][a-zA-Z0-9_]*/, sanitized, "")

    # Match :named_param
    Regex.scan(~r/:([a-zA-Z_][a-zA-Z0-9_]*)/, sanitized)
    |> Enum.map(fn [_, param] -> param end)
    |> Enum.uniq()
  end

  # --- Internal Helpers ---

  defp validate_sql(sql) when sql == "", do: {:error, "Query cannot be empty."}

  defp validate_sql(sql) do
    # Strip comments and string literals for keyword analysis
    stripped =
      sql
      |> String.replace(~r/'(?:''|[^'])*'/, "")
      |> String.replace(~r/\/\*.*?\*\//s, "")
      |> String.replace(~r/--.*$/m, "")
      |> String.trim()

    first_word =
      stripped
      |> String.split(~r/\s+/, parts: 2)
      |> List.first()
      |> to_string()
      |> String.upcase()

    cond do
      first_word not in ["SELECT", "WITH"] ->
        {:error, "Only SELECT or WITH queries are permitted."}

      contains_forbidden_keywords?(stripped) ->
        {:error, "Write or DDL statements are not permitted in queries."}

      true ->
        :ok
    end
  end

  defp contains_forbidden_keywords?(sql) do
    Enum.any?(@forbidden_keywords, fn kw ->
      Regex.match?(~r/\b#{kw}\b/i, sql)
    end)
  end

  defp bind_parameters(sql, params) when is_map(params) do
    # Find all named parameters in order of appearance
    named_params = extract_named_parameters(sql)

    # Param names are parsed out of user-authored SQL, so they must never
    # become atoms. Normalizing the caller's keys once lets atom- and
    # string-keyed maps read identically through a plain string lookup, and
    # preserves false/nil values that a `||` chain would skip.
    lookup = Map.new(params, fn {key, value} -> {to_string(key), value} end)

    {final_sql, bound_values, _} =
      Enum.reduce(named_params, {sql, [], 1}, fn param_name, {curr_sql, values, index} ->
        value = Map.get(lookup, param_name)
        regex = Regex.compile!(":#{param_name}\\b")
        replaced = Regex.replace(regex, curr_sql, "$#{index}")
        {replaced, values ++ [value], index + 1}
      end)

    {final_sql, bound_values}
  end

  defp bind_parameters(sql, params) when is_list(params) do
    {sql, params}
  end

  defp execute_in_readonly_transaction(
         sql,
         params,
         page,
         per_page,
         order_by,
         order_dir,
         timeout_ms
       ) do
    Repo.transaction(fn ->
      # Set PostgreSQL session variables for this transaction
      SQL.query!(Repo, "SET LOCAL default_transaction_read_only = on", [])

      # `timeout_ms` is an internal clamped integer from options/defaults, never reachable from client parameters.
      SQL.query!(Repo, "SET LOCAL statement_timeout = #{timeout_ms}", [])

      # 1. Count total rows
      count_sql = "SELECT COUNT(*) FROM (#{sql}) AS __blb_count"

      total =
        case SQL.query(Repo, count_sql, params) do
          {:ok, %Postgrex.Result{rows: [[count]]}} ->
            count

          {:error, %Postgrex.Error{postgres: %{message: msg}}} ->
            Repo.rollback("SQL error counting results: #{msg}")

          {:error, err} ->
            Repo.rollback("Database error: #{inspect(err)}")
        end

      # 2. Extract column metadata by running an empty sample or checking columns
      sample_sql = "SELECT * FROM (#{sql}) AS __blb_sample LIMIT 0"

      columns =
        case SQL.query(Repo, sample_sql, params) do
          {:ok, %Postgrex.Result{columns: cols}} ->
            cols

          {:error, %Postgrex.Error{postgres: %{message: msg}}} ->
            Repo.rollback("SQL error: #{msg}")

          {:error, err} ->
            Repo.rollback("Database error: #{inspect(err)}")
        end

      # 3. Build paginated query
      offset = (page - 1) * per_page

      order_clause =
        if is_binary(order_by) and order_by != "" and order_by in columns do
          dir = if order_dir in [:desc, "desc", "DESC"], do: "DESC", else: "ASC"
          " ORDER BY \"#{String.replace(order_by, "\"", "\"\"")}\" #{dir}"
        else
          ""
        end

      paginated_sql =
        "SELECT * FROM (#{sql}) AS __blb_view#{order_clause} LIMIT #{per_page} OFFSET #{offset}"

      rows =
        case SQL.query(Repo, paginated_sql, params) do
          {:ok, %Postgrex.Result{rows: raw_rows}} ->
            Enum.map(raw_rows, fn row_list ->
              Enum.zip(columns, row_list) |> Map.new()
            end)

          {:error, %Postgrex.Error{postgres: %{message: msg}}} ->
            Repo.rollback("SQL error executing query: #{msg}")

          {:error, err} ->
            Repo.rollback("Database error: #{inspect(err)}")
        end

      last_page = max(ceil(total / per_page), 1)

      %{
        columns: columns,
        rows: rows,
        total: total,
        total_count: total,
        page: page,
        per_page: per_page,
        last_page: last_page,
        total_pages: last_page
      }
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, other} -> {:error, inspect(other)}
    end
  end
end
