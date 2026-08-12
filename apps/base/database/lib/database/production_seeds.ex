defmodule Bilimbi.Base.Database.ProductionSeeds do
  @moduledoc false

  alias Bilimbi.Base.Database.ProductionSeed
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Ecto.Adapters.SQL

  @table "bilimbi_production_seeds"
  @interrupted_error "Seed execution was interrupted before completion and will be retried."

  @spec run(Ecto.Repo.t(), [ProductionSeed.t()], keyword()) ::
          {:ok, [map()]} | {:error, map()}
  def run(repo, seeds, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "public")
    table = qualified_table(prefix)
    ordered = order!(seeds)

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
  end

  @spec list_runs(Ecto.Repo.t(), keyword()) :: [map()]
  def list_runs(repo, opts \\ []) do
    table = qualified_table(Keyword.get(opts, :prefix, "public"))
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

    SQL.query!(
      repo,
      """
      CREATE INDEX IF NOT EXISTS "bilimbi_production_seeds_status_order_index"
      ON #{table} (status, module_order, seed_id)
      """,
      []
    )
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

  defp order!(seeds) when is_list(seeds) do
    unless Enum.all?(seeds, &match?(%ProductionSeed{}, &1)) do
      raise ArgumentError, "production seeds must be ProductionSeed structs"
    end

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
