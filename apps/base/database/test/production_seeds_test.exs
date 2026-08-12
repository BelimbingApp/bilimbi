defmodule Bilimbi.Base.Database.ProductionSeedsTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Database.ProductionSeed
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.ModuleRegistry
  alias Ecto.Adapters.SQL

  setup do
    SQL.query!(Repo, "CREATE TEMP TABLE seed_test_events (position bigserial, seed_id text)", [])

    prefix = temporary_schema!()
    quoted_prefix = SchemaVerifier.quote_identifier!(prefix)

    %{prefix: prefix, quoted_prefix: quoted_prefix}
  end

  test "runs in deterministic module and dependency order", context do
    seeds = [
      seed("base/database/zeta", insert_event(context, "zeta"), ["base/database/alpha"]),
      seed("base/module_registry/only", insert_event(context, "base")),
      seed("base/database/alpha", insert_event(context, "alpha"))
    ]

    assert {:ok,
            [
              %{id: "base/module_registry/only", status: :completed},
              %{id: "base/database/alpha", status: :completed},
              %{id: "base/database/zeta", status: :completed}
            ]} = run(seeds, context)

    assert event_ids(context) == ["base", "alpha", "zeta"]
  end

  test "registration is idempotent and completed seeds are skipped", context do
    definition = seed("base/database/idempotent", insert_event(context, "once"))

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
          ["base/database/retry"]
        ).rows

      if attempts == 1, do: {:error, :temporary_failure}, else: insert(context, "retried", repo)
    end

    definition = seed("base/database/retry", callback)
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
    definition = seed("base/database/interrupted", insert_event(context, "attempt"))
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
    definition = seed("base/database/not-applicable", fn _repo -> :skipped end)

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
             run([seed("base/database/adopted", fn _repo -> :ok end)], context)

    assert SQL.query!(
             Repo,
             "SELECT seeder_class, status, error_message FROM #{context.quoted_prefix}.base_database_seeders",
             []
           ).rows == [
             ["App\\Core\\Employee\\Database\\Seeders\\EmployeeTypeSeeder", "failed", "legacy"]
           ]
  end

  test "rejects duplicate, missing, backward, and cyclic dependencies", context do
    one = seed("base/database/one", fn _repo -> :ok end)
    duplicate = seed("base/database/one", fn _repo -> :ok end)

    assert_raise ArgumentError, "production seed IDs must be unique", fn ->
      run([one, duplicate], context)
    end

    missing =
      seed("base/database/missing", fn _repo -> :ok end, ["base/database/absent"])

    assert_raise ArgumentError, ~r/declares missing dependency/, fn ->
      run([missing], context)
    end

    later = seed("base/database/later", fn _repo -> :ok end)

    backward =
      seed("base/module_registry/backward", fn _repo -> :ok end, [later.id])

    assert_raise ArgumentError, ~r/depends on later module seed/, fn ->
      run([backward, later], context)
    end

    left =
      seed("base/database/left", fn _repo -> :ok end, ["base/database/right"])

    right = seed("base/database/right", fn _repo -> :ok end, [left.id])

    assert_raise ArgumentError, ~r/dependency cycle/, fn ->
      run([left, right], context)
    end
  end

  test "fails closed when an existing ledger has drifted from the expected shape", context do
    SQL.query!(
      Repo,
      """
      CREATE TABLE #{ledger(context)} (
        seed_id varchar(255) PRIMARY KEY,
        module_id varchar(255) NOT NULL
      )
      """,
      []
    )

    assert_raise ArgumentError, ~r/ledger shape drift/, fn ->
      run([seed("base/database/drift", fn _repo -> :ok end)], context)
    end
  end

  test "rejects a complete ledger whose status default could suppress callbacks", context do
    SQL.query!(
      Repo,
      """
      CREATE TABLE #{ledger(context)} (
        seed_id varchar(255) PRIMARY KEY,
        module_id varchar(255) NOT NULL,
        module_order integer NOT NULL,
        status varchar(20) NOT NULL DEFAULT 'completed',
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

    definition =
      seed("base/database/wrong-default", fn _repo ->
        send(self(), :seed_callback_invoked)
        :ok
      end)

    assert_raise ArgumentError, ~r/status: expected default/, fn ->
      run([definition], context)
    end

    refute_received :seed_callback_invoked
  end

  test "rejects a ledger missing the required status constraint", context do
    assert {:ok, []} = run([], context)

    SQL.query!(
      Repo,
      "ALTER TABLE #{ledger(context)} DROP CONSTRAINT bilimbi_production_seeds_status_check",
      []
    )

    assert_raise ArgumentError,
                 ~r/missing constraint bilimbi_production_seeds_status_check/,
                 fn ->
                   run([], context)
                 end
  end

  test "rejects stale workspace metadata before ledger or callback mutation", context do
    definition =
      seed("base/database/stale-graph", fn _repo ->
        send(self(), :seed_callback_invoked)
        :ok
      end)

    descriptor = Application.fetch_env!(:bilimbi_base_database, :bilimbi_module)

    on_exit(fn ->
      Application.put_env(:bilimbi_base_database, :bilimbi_module, descriptor)
    end)

    Application.put_env(
      :bilimbi_base_database,
      :bilimbi_module,
      Map.put(descriptor, :graph_fingerprint, "stale-test-fingerprint")
    )

    assert_raise ArgumentError, ~r/compiled from different workspace graphs/, fn ->
      run([definition], context)
    end

    refute_received :seed_callback_invoked

    assert [[nil]] =
             SQL.query!(
               Repo,
               "SELECT to_regclass($1)",
               [context.prefix <> ".bilimbi_production_seeds"]
             ).rows
  end

  defp seed(id, callback, dependencies \\ []) do
    module_id = id |> String.split("/") |> Enum.take(2) |> Enum.join("/")

    descriptor =
      ModuleRegistry.installed_modules!()
      |> Enum.find(&(&1.id == module_id))

    ProductionSeed.new!(
      id: id,
      module_id: module_id,
      module_order: descriptor.order,
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
