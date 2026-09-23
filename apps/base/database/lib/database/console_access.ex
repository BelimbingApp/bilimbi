defmodule Bilimbi.Base.Database.ConsoleAccess do
  @moduledoc """
  What the operator SQL console's PostgreSQL role may read, and the proof that
  its connection cannot write.

  The console runs through `Bilimbi.Base.Database.ConsoleRepo` as a role that
  holds `SELECT` and nothing else. `reconcile/2` grants that role `SELECT` on
  every table and view in the prefix schema, minus the columns the installed
  schema contracts name in `secret_columns/0`, and revokes every other
  privilege it holds there, sequences included, so re-running converges on
  exactly that set. `mix bilimbi.migrate` runs it after every migration.
  Every table is readable, rather than only the ones a contract declares,
  because contracts pin the compatible baseline and the tables Bilimbi added
  since are the ones an operator most needs to inspect.

  `held_write_privileges/1` asks PostgreSQL, as the console role, whether the
  connection could write anything: superuser, role- or database-creation
  flags, `CREATE` on the database or on a schema, or a write privilege on any
  relation. The executor runs it before every console query and refuses to
  run while the answer is not empty, so a console pointed at the
  application's own login fails visibly instead of reading through a
  read-write connection.
  """

  alias Bilimbi.Base.Database.ConsoleRepo
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.ModuleRegistry
  alias Ecto.Adapters.SQL

  @typedoc """
  What one reconciliation granted: `restricted` names the column-restricted
  tables, and `absent` the tables a contract names secrets on that do not
  exist in the prefix, which is reported rather than refused because a
  contract may know a table the database does not hold yet.
  """
  @type summary :: %{
          role: String.t(),
          tables: non_neg_integer(),
          restricted: [String.t()],
          absent: [String.t()]
        }

  @type failure ::
          {:role_missing, String.t()}
          | {:role_is_application_login, String.t()}
          | {:unknown_secret_column, String.t(), String.t()}

  @relation_kinds "('r', 'p', 'v', 'm', 'f', 'S')"

  # System schemas, every session's `pg_temp_N`, and `pg_toast` are excluded;
  # a temporary table is session-local and never durable data.
  @user_schema "n.nspname NOT LIKE 'pg\\_%' AND n.nspname <> 'information_schema'"

  @write_privileges_sql """
  WITH me AS (
    SELECT rolsuper, rolcreaterole, rolcreatedb, rolbypassrls
    FROM pg_roles
    WHERE rolname = current_user
  ),
  flags AS (
    SELECT reason
    FROM me, LATERAL (VALUES
      (rolsuper, 'is a superuser'),
      (rolcreaterole, 'may create roles'),
      (rolcreatedb, 'may create databases'),
      (rolbypassrls, 'bypasses row security'),
      (has_database_privilege(current_database(), 'CREATE'), 'may create schemas')
    ) AS held(held, reason)
    WHERE held
  ),
  schemas AS (
    SELECT 'may create objects in schema ' || quote_ident(n.nspname) AS reason
    FROM pg_namespace n
    WHERE #{@user_schema} AND has_schema_privilege(n.oid, 'CREATE')
  ),
  relations AS (
    SELECT 'may write ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname) AS reason
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE #{@user_schema}
      AND c.relkind IN #{@relation_kinds}
      AND CASE WHEN c.relkind = 'S'
            THEN has_sequence_privilege(c.oid, 'USAGE, UPDATE')
            ELSE has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE')
              OR has_any_column_privilege(c.oid, 'INSERT, UPDATE')
          END
  )
  SELECT current_user::text, reason FROM flags
  UNION ALL SELECT current_user::text, reason FROM schemas
  UNION ALL SELECT current_user::text, reason FROM relations
  LIMIT 10
  """

  @doc "The console role's name, as the console Repo is configured to connect."
  @spec role_name() :: String.t()
  def role_name do
    case Keyword.fetch(ConsoleRepo.config(), :username) do
      {:ok, username} when is_binary(username) and username != "" ->
        username

      _ ->
        raise ArgumentError,
              "#{inspect(ConsoleRepo)} has no username; configure CONSOLE_DATABASE_URL " <>
                "with the console's select-only role"
    end
  end

  @doc """
  Grants the console role exactly its reads in the given prefix schema.

  Runs through the application's own Repo, which owns the tables, inside one
  transaction: a failure changes nothing. Returns a summary, or a failure
  `explain/1` turns into operator instructions. `:contracts` overrides the
  installed schema contracts for tests.
  """
  @spec reconcile(Ecto.Repo.t(), keyword()) :: {:ok, summary()} | {:error, failure()}
  def reconcile(repo, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "public")
    contracts = Keyword.get_lazy(opts, :contracts, &installed_contracts/0)
    secrets = declared_secrets(contracts)
    role = role_name()

    repo.transaction(fn ->
      with :ok <- check_role(repo, role),
           {:ok, summary} <- apply_reads(repo, prefix, role, secrets) do
        summary
      else
        {:error, failure} -> repo.rollback(failure)
      end
    end)
  end

  @doc """
  Every way the connected role could write, as PostgreSQL reports it.

  Runs as the connected role and reads only the catalog. Empty means the
  connection cannot write anything durable.
  """
  @spec held_write_privileges(Ecto.Repo.t()) :: %{role: String.t() | nil, reasons: [String.t()]}
  def held_write_privileges(repo) do
    case SQL.query!(repo, @write_privileges_sql, []).rows do
      [] ->
        %{role: nil, reasons: []}

      [[role, _] | _] = rows ->
        %{role: role, reasons: Enum.map(rows, fn [_, reason] -> reason end)}
    end
  end

  @doc """
  Explains a `permission denied` on a table to the console user.

  Lists the columns the connected role may read, so a refused `SELECT *` on a
  column-restricted table says which columns to name instead.
  """
  @spec read_scope_hint(Ecto.Repo.t(), String.t()) :: String.t()
  def read_scope_hint(repo, relation) do
    case readable_columns(repo, relation) do
      {:ok, []} ->
        "The console has no read access to #{inspect(relation)}. Its reads are granted by " <>
          "`mix bilimbi.migrate`, so re-run it after adding a table; a table whose every " <>
          "column is secret stays unreadable."

      {:ok, columns} ->
        "The console can read only these columns of #{inspect(relation)}: " <>
          Enum.join(columns, ", ") <> ". Name them instead of *."

      :error ->
        ""
    end
  end

  @doc "One line describing a reconcile summary for an operator."
  @spec describe(summary()) :: String.t()
  def describe(%{role: role, tables: tables, restricted: restricted, absent: absent}) do
    "Console role #{inspect(role)} reads #{tables} tables" <>
      list(" (column-restricted: ", restricted, ")") <>
      list("; secrets declared on absent tables: ", absent, "") <> "."
  end

  @doc "Turns a reconcile failure into operator instructions."
  @spec explain(failure()) :: String.t()
  def explain({:role_missing, role}) do
    """
    The SQL console role #{inspect(role)} does not exist in this PostgreSQL cluster.

    The console connects through its own select-only role so that the database,
    not the application, refuses writes. Create the role as a superuser, point
    the console's connection at it (CONSOLE_DATABASE_URL in production,
    CONSOLE_PGUSER and CONSOLE_PGPASSWORD in development), and re-run
    `mix bilimbi.migrate`, which grants the role its reads:

        CREATE ROLE #{SchemaVerifier.quote_identifier!(role)} LOGIN PASSWORD '<password>';

    See docs/architecture/database.md, "Operator SQL console".
    """
  end

  def explain({:role_is_application_login, role}) do
    """
    The SQL console is configured to connect as #{inspect(role)}, which is the
    application's own database login. The console must connect through its own
    select-only role, never through the application's connection; see
    docs/architecture/database.md, "Operator SQL console".
    """
  end

  def explain({:unknown_secret_column, table, column}) do
    "#{inspect(table)} has no column #{inspect(column)}, which its schema contract names " <>
      "as secret."
  end

  # --- Declared secrets -----------------------------------------------------

  defp installed_contracts do
    ModuleRegistry.installed_modules!()
    |> Enum.reject(&is_nil(&1.schema_contract))
    |> Enum.map(& &1.schema_contract)
  end

  # `mix bilimbi.migrate` runs with applications configured but not started,
  # so a contract module may not be loaded yet; `function_exported?/3` alone
  # would then report no secrets and grant every column.
  defp declared_secrets(contracts) do
    Enum.reduce(contracts, %{}, fn contract, secrets ->
      if Code.ensure_loaded?(contract) and function_exported?(contract, :secret_columns, 0),
        do: Map.merge(secrets, contract.secret_columns(), fn _table, a, b -> a ++ b end),
        else: secrets
    end)
  end

  # --- Reconciliation -------------------------------------------------------

  defp check_role(repo, role) do
    %{rows: [[login, exists?]]} =
      SQL.query!(
        repo,
        "SELECT current_user::text, EXISTS (SELECT 1 FROM pg_roles WHERE rolname = $1)",
        [role]
      )

    cond do
      login == role -> {:error, {:role_is_application_login, role}}
      not exists? -> {:error, {:role_missing, role}}
      true -> :ok
    end
  end

  defp apply_reads(repo, prefix, role, secrets) do
    quoted_prefix = SchemaVerifier.quote_identifier!(prefix)
    quoted_role = SchemaVerifier.quote_identifier!(role)

    SQL.query!(repo, "GRANT USAGE ON SCHEMA #{quoted_prefix} TO #{quoted_role}", [])

    relations = relations(repo, prefix)
    present = Enum.map(relations, fn {name, _kind} -> name end)
    absent = secrets |> Map.keys() |> Enum.reject(&(&1 in present)) |> Enum.sort()

    Enum.reduce_while(
      relations,
      {:ok, %{role: role, tables: 0, restricted: [], absent: absent}},
      fn
        {name, "S"}, {:ok, summary} ->
          revoke_all!(repo, quoted_prefix, name, "S", quoted_role)
          {:cont, {:ok, summary}}

        {name, kind}, {:ok, summary} ->
          case grant_read(repo, quoted_prefix, prefix, name, kind, secrets[name], quoted_role) do
            :whole ->
              {:cont, {:ok, %{summary | tables: summary.tables + 1}}}

            :columns ->
              {:cont,
               {:ok,
                %{summary | tables: summary.tables + 1, restricted: summary.restricted ++ [name]}}}

            {:error, failure} ->
              {:halt, {:error, failure}}
          end
      end
    )
  end

  defp grant_read(repo, quoted_prefix, _prefix, name, kind, nil, quoted_role) do
    qualified = "#{quoted_prefix}.#{SchemaVerifier.quote_identifier!(name)}"
    revoke_all!(repo, quoted_prefix, name, kind, quoted_role)
    SQL.query!(repo, "GRANT SELECT ON TABLE #{qualified} TO #{quoted_role}", [])
    :whole
  end

  defp grant_read(repo, quoted_prefix, prefix, name, kind, secrets, quoted_role) do
    columns = columns(repo, prefix, name)

    case Enum.find(secrets, &(&1 not in columns)) do
      nil ->
        qualified = "#{quoted_prefix}.#{SchemaVerifier.quote_identifier!(name)}"
        revoke_all!(repo, quoted_prefix, name, kind, quoted_role)

        case Enum.map_join(columns -- secrets, ", ", &SchemaVerifier.quote_identifier!/1) do
          "" ->
            :ok

          readable ->
            SQL.query!(
              repo,
              "GRANT SELECT (#{readable}) ON TABLE #{qualified} TO #{quoted_role}",
              []
            )
        end

        :columns

      column ->
        {:error, {:unknown_secret_column, name, column}}
    end
  end

  defp revoke_all!(repo, quoted_prefix, name, kind, quoted_role) do
    object = if kind == "S", do: "SEQUENCE", else: "TABLE"
    qualified = "#{quoted_prefix}.#{SchemaVerifier.quote_identifier!(name)}"
    SQL.query!(repo, "REVOKE ALL PRIVILEGES ON #{object} #{qualified} FROM #{quoted_role}", [])
  end

  # Every relation in the prefix, sequences included, so the grants converge
  # on the whole schema and any hand grant is taken back.
  defp relations(repo, prefix) do
    SQL.query!(
      repo,
      """
      SELECT c.relname, c.relkind::text
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = $1 AND c.relkind IN #{@relation_kinds}
      ORDER BY c.relname
      """,
      [prefix]
    ).rows
    |> Enum.map(fn [name, kind] -> {name, kind} end)
  end

  defp columns(repo, prefix, name) do
    SQL.query!(
      repo,
      """
      SELECT a.attname
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = $1 AND c.relname = $2 AND a.attnum > 0 AND NOT a.attisdropped
      ORDER BY a.attnum
      """,
      [prefix, name]
    ).rows
    |> Enum.map(fn [column] -> column end)
  end

  defp readable_columns(repo, relation) do
    case SQL.query(
           repo,
           """
           SELECT a.attname
           FROM pg_class c
           JOIN pg_namespace n ON n.oid = c.relnamespace
           JOIN pg_attribute a ON a.attrelid = c.oid
           WHERE c.relname = $1
             AND n.nspname = ANY (current_schemas(false))
             AND a.attnum > 0 AND NOT a.attisdropped
             AND has_column_privilege(c.oid, a.attnum, 'SELECT')
           ORDER BY a.attnum
           """,
           [relation]
         ) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, fn [column] -> column end)}
      {:error, _error} -> :error
    end
  end

  defp list(_lead, [], _trail), do: ""
  defp list(lead, names, trail), do: lead <> Enum.join(names, ", ") <> trail
end
