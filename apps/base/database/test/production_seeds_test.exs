defmodule Bilimbi.Base.Database.ProductionSeedsTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Database.ProductionSeed
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Ecto.Adapters.SQL

  setup do
    SQL.query!(Repo, "CREATE TEMP TABLE seed_test_events (position bigserial, seed_id text)", [])

    prefix = temporary_schema!()
    quoted_prefix = SchemaVerifier.quote_identifier!(prefix)

    %{prefix: prefix, quoted_prefix: quoted_prefix}
  end

  test "runs in deterministic module and dependency order", context do
    seeds = [
      seed("core/sample/zeta", 3, insert_event(context, "zeta"), ["core/sample/alpha"]),
      seed("base/reference/only", 0, insert_event(context, "base")),
      seed("core/sample/alpha", 3, insert_event(context, "alpha"))
    ]

    assert {:ok,
            [
              %{id: "base/reference/only", status: :completed},
              %{id: "core/sample/alpha", status: :completed},
              %{id: "core/sample/zeta", status: :completed}
            ]} = run(seeds, context)

    assert event_ids(context) == ["base", "alpha", "zeta"]
  end

  test "registration is idempotent and completed seeds are skipped", context do
    definition = seed("core/sample/idempotent", 2, insert_event(context, "once"))

    assert {:ok, [%{status: :completed}]} = run([definition], context)
    assert {:ok, [%{status: :skipped}]} = run([definition], context)
    assert event_ids(context) == ["once"]

    assert [state] = list_runs(context)
    assert state.id == definition.id
    assert state.status == :completed
    assert state.attempts == 1
    assert state.completed_at
    refute state.error_message
  end

  test "failed seeds stop the run and retry on the next invocation", context do
    callback = fn repo ->
      [[attempts]] =
        SQL.query!(
          repo,
          "SELECT attempts FROM #{ledger(context)} WHERE seed_id = $1",
          ["core/sample/retry"]
        ).rows

      if attempts == 1, do: {:error, :temporary_failure}, else: insert(context, "retried", repo)
    end

    definition = seed("core/sample/retry", 2, callback)
    definition_id = definition.id

    assert {:error, %{seed_id: ^definition_id, reason: :temporary_failure}} =
             run([definition], context)

    assert [failed] = list_runs(context)
    assert failed.status == :failed
    assert failed.attempts == 1
    assert failed.error_message =~ "temporary_failure"

    assert {:ok, [%{status: :completed}]} = run([definition], context)
    assert event_ids(context) == ["retried"]

    assert [completed] = list_runs(context)
    assert completed.status == :completed
    assert completed.attempts == 2
    refute completed.error_message
  end

  test "interrupted running entries become retryable", context do
    definition = seed("core/sample/interrupted", 2, insert_event(context, "attempt"))
    assert {:ok, [%{status: :completed}]} = run([definition], context)

    SQL.query!(
      Repo,
      "UPDATE #{ledger(context)} SET status = 'running', completed_at = NULL WHERE seed_id = $1",
      [definition.id]
    )

    assert {:ok, [%{status: :completed}]} = run([definition], context)
    assert event_ids(context) == ["attempt", "attempt"]

    assert [state] = list_runs(context)
    assert state.status == :completed
    assert state.attempts == 2
  end

  test "callbacks can record an observable skipped terminal state", context do
    definition = seed("core/sample/not-applicable", 2, fn _repo -> :skipped end)

    assert {:ok, [%{status: :skipped}]} = run([definition], context)
    assert {:ok, [%{status: :skipped}]} = run([definition], context)

    assert [state] = list_runs(context)
    assert state.status == :skipped
    assert state.attempts == 1
    assert state.completed_at
  end

  test "an adopted Laravel seeder ledger is preserved byte-for-byte", context do
    SQL.query!(
      Repo,
      """
      CREATE TABLE #{context.quoted_prefix}.base_database_seeders (
        seeder_class text PRIMARY KEY,
        status text NOT NULL,
        error_message text
      )
      """,
      []
    )

    SQL.query!(
      Repo,
      "INSERT INTO #{context.quoted_prefix}.base_database_seeders VALUES ($1, $2, $3)",
      ["App\\Core\\Employee\\Database\\Seeders\\EmployeeTypeSeeder", "failed", "legacy"]
    )

    assert {:ok, [%{status: :completed}]} =
             run([seed("core/sample/adopted", 2, fn _repo -> :ok end)], context)

    assert SQL.query!(
             Repo,
             "SELECT seeder_class, status, error_message FROM #{context.quoted_prefix}.base_database_seeders",
             []
           ).rows == [
             ["App\\Core\\Employee\\Database\\Seeders\\EmployeeTypeSeeder", "failed", "legacy"]
           ]
  end

  test "rejects duplicate, missing, backward, and cyclic dependencies", context do
    one = seed("core/sample/one", 2, fn _repo -> :ok end)
    duplicate = seed("core/sample/one", 2, fn _repo -> :ok end)

    assert_raise ArgumentError, "production seed IDs must be unique", fn ->
      run([one, duplicate], context)
    end

    missing = seed("core/sample/missing", 2, fn _repo -> :ok end, ["core/sample/absent"])

    assert_raise ArgumentError, ~r/declares missing dependency/, fn ->
      run([missing], context)
    end

    later = seed("core/later/value", 3, fn _repo -> :ok end)
    backward = seed("base/early/value", 0, fn _repo -> :ok end, [later.id])

    assert_raise ArgumentError, ~r/depends on later module seed/, fn ->
      run([backward, later], context)
    end

    left = seed("core/sample/left", 2, fn _repo -> :ok end, ["core/sample/right"])
    right = seed("core/sample/right", 2, fn _repo -> :ok end, [left.id])

    assert_raise ArgumentError, ~r/dependency cycle/, fn ->
      run([left, right], context)
    end
  end

  defp seed(id, order, callback, dependencies \\ []) do
    module_id = id |> String.split("/") |> Enum.take(2) |> Enum.join("/")

    ProductionSeed.new!(
      id: id,
      module_id: module_id,
      module_order: order,
      callback: callback,
      dependencies: dependencies
    )
  end

  defp insert_event(context, id) do
    fn repo -> insert(context, id, repo) end
  end

  defp insert(context, id, repo) do
    SQL.query!(
      repo,
      "INSERT INTO #{context.quoted_prefix}.seed_test_events (seed_id) VALUES ($1)",
      [
        id
      ]
    )

    :ok
  end

  defp event_ids(context) do
    SQL.query!(
      Repo,
      "SELECT seed_id FROM #{context.quoted_prefix}.seed_test_events ORDER BY position",
      []
    ).rows
    |> List.flatten()
  end

  defp run(seeds, context) do
    Database.run_production_seeds(seeds, repo: Repo, prefix: context.prefix)
  end

  defp list_runs(context) do
    Database.list_production_seed_runs(repo: Repo, prefix: context.prefix)
  end

  defp ledger(context),
    do:
      context.quoted_prefix <> "." <> SchemaVerifier.quote_identifier!("bilimbi_production_seeds")
end
