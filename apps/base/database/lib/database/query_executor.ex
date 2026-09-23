defmodule Bilimbi.Base.Database.QueryExecutor do
  @moduledoc """
  Safe, read-only SQL query execution engine.

  Runs user-defined SQL through `Bilimbi.Base.Database.ConsoleRepo`, the
  console's own connection as a PostgreSQL role holding `SELECT` and nothing
  else, inside a `READ ONLY` transaction with a statement timeout and a row
  limit. Before every run it asks PostgreSQL whether that connection could
  write anything and refuses to run while it could, so a misconfigured
  console fails visibly rather than reading through the application's
  read-write connection.

  The text checks that reject anything but a `SELECT`/`WITH` statement and
  known write/DDL keywords give early, readable refusals. They are not the
  boundary: the role's privileges are, and the read-only transaction backs
  them up for what privileges do not cover, such as temporary objects.
  """

  alias Bilimbi.Base.Database.ConsoleAccess
  alias Bilimbi.Base.Database.ConsoleRepo
  alias Ecto.Adapters.SQL

  @max_rows 1000
  @default_timeout_ms 10_000

  # Refused before reaching PostgreSQL so the operator gets a plain sentence
  # instead of a privilege error; the database refuses these regardless.
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
    ConsoleRepo.transaction(fn ->
      # `SET TRANSACTION READ ONLY` applies to the transaction already open
      # here. (The similar-looking `SET LOCAL default_transaction_read_only =
      # on` only sets the default for *later* transactions and leaves this
      # one read-write.) It is the second line: the connection's role holds
      # no write privilege, and `refuse_writable_connection!/0` proves that
      # on every run.
      SQL.query!(ConsoleRepo, "SET TRANSACTION READ ONLY", [])

      # `timeout_ms` is an internal clamped integer from options/defaults, never reachable from client parameters.
      SQL.query!(ConsoleRepo, "SET LOCAL statement_timeout = #{timeout_ms}", [])

      refuse_writable_connection!()

      # 1. Count total rows
      count_sql = "SELECT COUNT(*) FROM (#{sql}) AS __blb_count"

      total =
        case SQL.query(ConsoleRepo, count_sql, params) do
          {:ok, %Postgrex.Result{rows: [[count]]}} ->
            count

          {:error, %Postgrex.Error{postgres: %{message: msg}}} ->
            ConsoleRepo.rollback("SQL error counting results: #{msg}")

          {:error, err} ->
            ConsoleRepo.rollback("Database error: #{inspect(err)}")
        end

      # 2. Extract column metadata by running an empty sample or checking columns
      sample_sql = "SELECT * FROM (#{sql}) AS __blb_sample LIMIT 0"

      columns =
        case SQL.query(ConsoleRepo, sample_sql, params) do
          {:ok, %Postgrex.Result{columns: cols}} ->
            cols

          {:error, %Postgrex.Error{postgres: %{message: msg}}} ->
            ConsoleRepo.rollback("SQL error: #{msg}")

          {:error, err} ->
            ConsoleRepo.rollback("Database error: #{inspect(err)}")
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
        case SQL.query(ConsoleRepo, paginated_sql, params) do
          {:ok, %Postgrex.Result{rows: raw_rows}} ->
            Enum.map(raw_rows, fn row_list ->
              Enum.zip(columns, row_list) |> Map.new()
            end)

          {:error, %Postgrex.Error{postgres: %{message: msg}}} ->
            ConsoleRepo.rollback("SQL error executing query: #{msg}")

          {:error, err} ->
            ConsoleRepo.rollback("Database error: #{inspect(err)}")
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
      {:error, reason} when is_binary(reason) -> {:error, explain_permission_denied(reason)}
      {:error, other} -> {:error, inspect(other)}
    end
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error,
       "The database console cannot connect through its select-only role: " <>
         "#{Exception.message(error)}. Check its connection (see " <>
         "docs/architecture/database.md, \"Operator SQL console\")."}
  end

  # A console that could write would reinstate the hole the select-only role
  # closes, so it does not run at all. Asking PostgreSQL, rather than reading
  # a configuration value, is what makes the refusal true.
  defp refuse_writable_connection! do
    case ConsoleAccess.held_write_privileges(ConsoleRepo) do
      %{reasons: []} ->
        :ok

      %{role: role, reasons: reasons} ->
        ConsoleRepo.rollback(
          "The database console cannot run because its connection can write: role " <>
            "#{inspect(role)} #{Enum.join(reasons, "; ")}. Connect the console through " <>
            "its select-only role (see docs/architecture/database.md, \"Operator SQL " <>
            "console\") and run `mix bilimbi.migrate` to grant its reads."
        )
    end
  end

  # A column-restricted table refuses `SELECT *` with a bare "permission
  # denied"; say which columns the console may name instead.
  @permission_denied ~r/permission denied for (?:table|view|materialized view) "?([^"\s]+)"?/

  defp explain_permission_denied(reason) do
    case Regex.run(@permission_denied, reason) do
      [_, relation] -> reason <> " " <> ConsoleAccess.read_scope_hint(ConsoleRepo, relation)
      nil -> reason
    end
  end
end
