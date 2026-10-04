defmodule Bilimbi.Base.Database.ProductionSeeds do
  @moduledoc false

  alias Bilimbi.Base.Database.ProductionSeed
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.ModuleRegistry
  alias Ecto.Adapters.SQL

  @table "bilimbi_production_seeds"
  @interrupted_error "Seed execution was interrupted before completion and will be retried."
  # `pg_get_constraintdef` expands `status IN (...)` into this form. SchemaVerifier
  # compares the normalised expression, so the spec names what PostgreSQL stores.
  @status_check_expression "CHECK (status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'skipped'::character varying]::text[]))"

  @provider_key :bilimbi_production_seed_provider

  @spec installed!([module()]) :: [ProductionSeed.t()]
  def installed!(extra_providers) do
    modules = ModuleRegistry.installed_modules!()

    modules
    |> Enum.flat_map(fn descriptor ->
      descriptor.otp_app
      |> Application.get_env(@provider_key, [])
      |> List.wrap()
    end)
    |> Kernel.++(extra_providers)
    |> Enum.uniq()
    |> Enum.flat_map(&provider_seeds!(&1, modules))
  end

  defp provider_seeds!(provider, modules) do
    unless Code.ensure_loaded?(provider) and function_exported?(provider, :production_seeds, 0) do
      raise ArgumentError, "#{inspect(provider)} is not a production seed provider"
    end

    behaviours =
      provider.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    unless Bilimbi.Base.Database.ProductionSeedProvider in behaviours do
      raise ArgumentError,
            "#{inspect(provider)} must implement Bilimbi.Base.Database.ProductionSeedProvider"
    end

    otp_app =
      Application.get_application(provider) ||
        raise ArgumentError, "#{inspect(provider)} is not loaded from an OTP application"

    descriptor =
      Enum.find(modules, &(&1.otp_app == otp_app)) ||
        raise ArgumentError, "#{inspect(otp_app)} has no installed Bilimbi module metadata"

    seeds = provider.production_seeds()

    Enum.each(seeds, fn seed ->
      unless seed.module_id == descriptor.id do
        raise ArgumentError,
              "production seed #{seed.id} belongs to #{seed.module_id}, but provider " <>
                "#{inspect(provider)} is installed as #{descriptor.id}"
      end
    end)

    seeds
  end

  @spec run(Ecto.Repo.t(), [ProductionSeed.t()], keyword()) ::
          {:ok, [map()]} | {:error, map()}
  def run(repo, seeds, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "public")
    table = qualified_table(prefix)
    ordered = order!(seeds, ModuleRegistry.installed_modules!())

    # Seeding is infrastructure, not an actor's mutation — the source skips
    # its listener while seeding, and ADR 0013 ports that as the capture
    # kill switch.
    Bilimbi.Base.Database.WriteCapture.without_capture(fn ->
      repo.checkout(fn ->
        lock!(repo, prefix)

        try do
          ensure_ledger!(repo, table)
          recover_interrupted!(repo, table)
          register!(repo, table, ordered)
          execute(repo, table, ordered)
        after
          unlock!(repo, prefix)
        end
      end)
    end)
  end

  @spec list_runs(Ecto.Repo.t(), keyword()) :: [map()]
  def list_runs(repo, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "public")
    table = qualified_table(prefix)

    repo.checkout(fn ->
      lock!(repo, prefix)

      try do
        ensure_ledger!(repo, table)

        SQL.query!(
          repo,
          """
          SELECT seed_id, module_id, module_order, status, attempts,
                 started_at, completed_at, error_message
          FROM #{table}
          ORDER BY module_order, seed_id
          """,
          []
        ).rows
        |> Enum.map(&run_from_row/1)
      after
        unlock!(repo, prefix)
      end
    end)
  end

  defp ensure_ledger!(repo, table) do
    SQL.query!(
      repo,
      """
      CREATE TABLE IF NOT EXISTS #{table} (
        seed_id varchar(255) PRIMARY KEY,
        module_id varchar(255) NOT NULL,
        module_order integer NOT NULL,
        status varchar(20) NOT NULL DEFAULT 'pending',
        attempts integer NOT NULL DEFAULT 0,
        started_at timestamp(0) without time zone,
        completed_at timestamp(0) without time zone,
        error_message text,
        inserted_at timestamp(0) without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at timestamp(0) without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT bilimbi_production_seeds_status_check
          CHECK (status IN ('pending', 'running', 'completed', 'failed', 'skipped'))
      )
      """,
      []
    )

    {prefix, _bare_table} = split_qualified_table(table)
    # Columns and the status check are proved before the index statement. A
    # drifted table must raise here; creating the index first would fail in
    # PostgreSQL on a column that is not there, and that error is not the
    # ledger-drift refusal.
    verify_ledger!(repo, prefix, ledger_spec(status_index_optional: true))

    SQL.query!(
      repo,
      """
      CREATE INDEX IF NOT EXISTS "bilimbi_production_seeds_status_order_index"
      ON #{table} (status, module_order, seed_id)
      """,
      []
    )

    verify_ledger!(repo, prefix, ledger_spec())
  end

  defp verify_ledger!(repo, prefix, spec) do
    case SchemaVerifier.verify(repo, [spec], prefix: prefix) do
      :ok -> :ok
      {:error, messages} -> raise_ledger_drift!(messages)
    end
  end

  # The ledger is a SchemaVerifier table spec. Do not read information_schema
  # or pg_index for it; that was a second drift engine beside the one every
  # module contract already uses.
  defp ledger_spec(opts \\ []) do
    pkey = %{columns: ["seed_id"], unique: true, where: nil}

    status_index = %{
      columns: ["status", "module_order", "seed_id"],
      unique: false,
      where: nil
    }

    # Before CREATE INDEX, the status index may already be there (a second
    # run) or not (a fresh table). It is optional on that first check so an
    # existing correct index is not "unexpected", and required once created.
    {indexes, optional_indexes} =
      if Keyword.get(opts, :status_index_optional, false) do
        {%{"bilimbi_production_seeds_pkey" => pkey},
         %{"bilimbi_production_seeds_status_order_index" => status_index}}
      else
        {%{
           "bilimbi_production_seeds_pkey" => pkey,
           "bilimbi_production_seeds_status_order_index" => status_index
         }, %{}}
      end

    spec = %{
      name: @table,
      columns: %{
        "seed_id" => column({:varchar, 255}, false),
        "module_id" => column({:varchar, 255}, false),
        "module_order" => column(:integer, false),
        "status" => column({:varchar, 20}, false, {:string, "pending"}),
        "attempts" => column(:integer, false, {:integer, 0}),
        "started_at" => column({:timestamp, 0}),
        "completed_at" => column({:timestamp, 0}),
        "error_message" => column(:text),
        "inserted_at" => column({:timestamp, 0}, false, :current_timestamp),
        "updated_at" => column({:timestamp, 0}, false, :current_timestamp)
      },
      indexes: indexes,
      foreign_keys: %{},
      checks: %{
        "bilimbi_production_seeds_status_check" => %{
          expression: @status_check_expression,
          validated: true
        }
      }
    }

    if optional_indexes == %{} do
      spec
    else
      Map.put(spec, :optional_indexes, optional_indexes)
    end
  end

  defp column(type, nullable \\ true, default \\ nil) do
    %{type: type, nullable: nullable, default: default}
  end

  defp raise_ledger_drift!(messages) do
    raise ArgumentError,
          "bilimbi_production_seeds ledger shape drift: " <>
            Enum.join(Enum.sort(messages), "; ")
  end

  defp split_qualified_table(qualified_table) do
    case Regex.run(~r/^"([^"]+)"\."([^"]+)"$/, qualified_table) do
      [_, prefix, table] -> {prefix, table}
      _ -> raise ArgumentError, "invalid qualified ledger table: #{qualified_table}"
    end
  end

  defp recover_interrupted!(repo, table) do
    SQL.query!(
      repo,
      """
      UPDATE #{table}
      SET status = 'failed', error_message = $1, updated_at = CURRENT_TIMESTAMP
      WHERE status = 'running'
      """,
      [@interrupted_error]
    )
  end

  defp register!(repo, table, seeds) do
    Enum.each(seeds, fn seed ->
      SQL.query!(
        repo,
        """
        INSERT INTO #{table} (seed_id, module_id, module_order)
        VALUES ($1, $2, $3)
        ON CONFLICT (seed_id) DO UPDATE
        SET module_id = EXCLUDED.module_id,
            module_order = EXCLUDED.module_order,
            updated_at = CURRENT_TIMESTAMP
        """,
        [seed.id, seed.module_id, seed.module_order]
      )
    end)
  end

  defp execute(repo, table, seeds) do
    Enum.reduce_while(seeds, {:ok, []}, fn seed, {:ok, results} ->
      case status(repo, table, seed.id) do
        status when status in ["completed", "skipped"] ->
          {:cont, {:ok, [%{id: seed.id, status: :skipped} | results]}}

        _status ->
          case execute_one(repo, table, seed) do
            {:ok, status} ->
              {:cont, {:ok, [%{id: seed.id, status: status} | results]}}

            {:error, reason} ->
              {:halt,
               {:error, %{seed_id: seed.id, reason: reason, results: Enum.reverse(results)}}}
          end
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  defp execute_one(repo, table, seed) do
    mark_running!(repo, table, seed.id)

    try do
      case ProductionSeed.invoke(seed, repo) do
        :ok ->
          mark_terminal!(repo, table, seed.id, "completed")
          {:ok, :completed}

        :skipped ->
          mark_terminal!(repo, table, seed.id, "skipped")
          {:ok, :skipped}

        {:error, reason} ->
          fail(repo, table, seed.id, reason)

        other ->
          fail(repo, table, seed.id, {:invalid_return, other})
      end
    rescue
      error ->
        reason = Exception.message(error)
        mark_failed!(repo, table, seed.id, reason)
        {:error, reason}
    catch
      kind, reason ->
        message = Exception.format(kind, reason, __STACKTRACE__)
        mark_failed!(repo, table, seed.id, message)
        {:error, reason}
    end
  end

  defp fail(repo, table, seed_id, reason) do
    mark_failed!(repo, table, seed_id, inspect(reason))
    {:error, reason}
  end

  defp mark_running!(repo, table, seed_id) do
    SQL.query!(
      repo,
      """
      UPDATE #{table}
      SET status = 'running', attempts = attempts + 1,
          started_at = CURRENT_TIMESTAMP, completed_at = NULL,
          error_message = NULL, updated_at = CURRENT_TIMESTAMP
      WHERE seed_id = $1
      """,
      [seed_id]
    )
  end

  defp mark_terminal!(repo, table, seed_id, status) when status in ["completed", "skipped"] do
    SQL.query!(
      repo,
      """
      UPDATE #{table}
      SET status = $2, completed_at = CURRENT_TIMESTAMP,
          error_message = NULL, updated_at = CURRENT_TIMESTAMP
      WHERE seed_id = $1
      """,
      [seed_id, status]
    )
  end

  defp mark_failed!(repo, table, seed_id, message) do
    SQL.query!(
      repo,
      """
      UPDATE #{table}
      SET status = 'failed', error_message = $2, updated_at = CURRENT_TIMESTAMP
      WHERE seed_id = $1
      """,
      [seed_id, message]
    )
  end

  defp status(repo, table, seed_id) do
    [[status]] =
      SQL.query!(repo, "SELECT status FROM #{table} WHERE seed_id = $1", [seed_id]).rows

    status
  end

  defp order!(seeds, modules) when is_list(seeds) do
    unless Enum.all?(seeds, &match?(%ProductionSeed{}, &1)) do
      raise ArgumentError, "production seeds must be ProductionSeed structs"
    end

    modules_by_id = Map.new(modules, &{&1.id, &1})

    Enum.each(seeds, fn seed ->
      module =
        Map.get(modules_by_id, seed.module_id) ||
          raise ArgumentError,
                "production seed #{seed.id} belongs to uninstalled module #{seed.module_id}"

      unless seed.module_order == module.order do
        raise ArgumentError,
              "production seed #{seed.id} has stale module order #{seed.module_order}; " <>
                "installed order is #{module.order}"
      end
    end)

    by_id = Map.new(seeds, &{&1.id, &1})

    if map_size(by_id) != length(seeds) do
      raise ArgumentError, "production seed IDs must be unique"
    end

    Enum.each(seeds, fn seed ->
      Enum.each(seed.dependencies, fn dependency_id ->
        dependency =
          Map.get(by_id, dependency_id) ||
            raise ArgumentError,
                  "production seed #{seed.id} declares missing dependency #{dependency_id}"

        if dependency.module_order > seed.module_order do
          raise ArgumentError,
                "production seed #{seed.id} depends on later module seed #{dependency_id}"
        end
      end)
    end)

    indegrees = Map.new(seeds, &{&1.id, length(&1.dependencies)})

    dependents =
      Enum.reduce(seeds, %{}, fn seed, acc ->
        Enum.reduce(seed.dependencies, acc, fn dependency_id, nested_acc ->
          Map.update(nested_acc, dependency_id, [seed.id], &[seed.id | &1])
        end)
      end)

    queue = Enum.filter(seeds, &(indegrees[&1.id] == 0))
    {ordered, remaining} = sort_queue(queue, [], indegrees, dependents, by_id)

    if map_size(remaining) != 0 do
      cycle_ids = remaining |> Map.keys() |> Enum.sort() |> Enum.join(", ")
      raise ArgumentError, "production seed dependency cycle: #{cycle_ids}"
    end

    Enum.reverse(ordered)
  end

  defp sort_queue([], ordered, indegrees, _dependents, _by_id),
    do: {ordered, Enum.reject(indegrees, fn {_id, degree} -> degree == 0 end) |> Map.new()}

  defp sort_queue(queue, ordered, indegrees, dependents, by_id) do
    [seed | rest] = Enum.sort_by(queue, &{&1.module_order, &1.id})

    {next_queue, next_indegrees} =
      dependents
      |> Map.get(seed.id, [])
      |> Enum.reduce({rest, Map.put(indegrees, seed.id, 0)}, fn dependent_id, {queued, degrees} ->
        degree = Map.fetch!(degrees, dependent_id) - 1
        degrees = Map.put(degrees, dependent_id, degree)

        if degree == 0 do
          {[Map.fetch!(by_id, dependent_id) | queued], degrees}
        else
          {queued, degrees}
        end
      end)

    sort_queue(next_queue, [seed | ordered], next_indegrees, dependents, by_id)
  end

  defp lock!(repo, prefix) do
    # hashtext/1 has a 32-bit key space. A collision only over-serializes two
    # unrelated prefixes; it cannot allow their seed queues to overlap.
    SQL.query!(repo, "SELECT pg_advisory_lock(hashtext($1))", [lock_key(prefix)])
  end

  defp unlock!(repo, prefix) do
    SQL.query!(repo, "SELECT pg_advisory_unlock(hashtext($1))", [lock_key(prefix)])
  end

  defp lock_key(prefix), do: "bilimbi-production-seeds:#{prefix}"

  defp qualified_table(prefix) do
    SchemaVerifier.quote_identifier!(prefix) <> "." <> SchemaVerifier.quote_identifier!(@table)
  end

  defp run_from_row([
         seed_id,
         module_id,
         module_order,
         status,
         attempts,
         started_at,
         completed_at,
         error_message
       ]) do
    %{
      id: seed_id,
      module_id: module_id,
      module_order: module_order,
      status: status_atom(status),
      attempts: attempts,
      started_at: started_at,
      completed_at: completed_at,
      error_message: error_message
    }
  end

  defp status_atom("pending"), do: :pending
  defp status_atom("running"), do: :running
  defp status_atom("completed"), do: :completed
  defp status_atom("failed"), do: :failed
  defp status_atom("skipped"), do: :skipped
end
