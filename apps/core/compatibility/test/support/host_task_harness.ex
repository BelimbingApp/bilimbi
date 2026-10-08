defmodule Bilimbi.Core.Compatibility.HostTaskHarness do
  @moduledoc """
  Runs the operational Mix tasks against a throwaway database, as an operator
  runs them.

  Production entry points refuse a runtime that cannot see the whole graph
  (`ModuleRegistry.complete_modules!/0`). This package's closure is partial,
  so host tasks run from the umbrella root; package-local commands run here.
  Every nested command is recorded for the failure diagnostics supplement.

  `setup_databases/1` is the `setup` body shared by the end-to-end tests: a
  maintenance connection that creates the database, a one-connection repo on
  it, and the environment the nested commands need to reach it.
  """

  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 1, start_supervised!: 1]

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Compatibility.MigrationTestRepo
  alias Bilimbi.Core.Compatibility.PlatformBaselineFailureDiagnostics
  alias Bilimbi.Core.Compatibility.PlatformBaselineTestRepo
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  @package_root Path.expand("../..", __DIR__)
  @workspace_root Path.expand("../../../../..", __DIR__)
  @host_tasks ~w(bilimbi.migrate bilimbi.rollback bilimbi.schema.verify bilimbi.schema.adopt bilimbi.seeds.run)

  @doc "The umbrella root the host tasks run from."
  def workspace_root, do: @workspace_root

  @doc false
  def setup_databases(%{base_env: base_env} = context) do
    PlatformBaselineFailureDiagnostics.capture(context, :setup, fn ->
      repo_options =
        Repo.config()
        |> Keyword.put(:name, MigrationTestRepo)
        |> Keyword.put(:pool, DBConnection.ConnectionPool)
        |> Keyword.put(:pool_size, 4)

      Application.put_env(:bilimbi_base_database, MigrationTestRepo, repo_options)

      on_exit(fn ->
        PlatformBaselineFailureDiagnostics.capture(context, :cleanup, fn ->
          Application.delete_env(:bilimbi_base_database, MigrationTestRepo)
        end)
      end)

      start_supervised!(MigrationTestRepo)

      partition =
        "bilimbi_e2e_#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}"

      database = "bilimbi_test_#{partition}"
      quoted_database = SchemaVerifier.quote_identifier!(database)

      SQL.query!(MigrationTestRepo, "CREATE DATABASE #{quoted_database}", [])

      on_exit(fn ->
        PlatformBaselineFailureDiagnostics.capture(context, :cleanup, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            SQL.query!(Repo, "DROP DATABASE IF EXISTS #{quoted_database} WITH (FORCE)", [])
          end)
        end)
      end)

      platform_repo_options =
        Repo.config()
        |> Keyword.put(:name, PlatformBaselineTestRepo)
        |> Keyword.put(:database, database)
        |> Keyword.put(:pool, DBConnection.ConnectionPool)
        |> Keyword.put(:pool_size, 1)

      Application.put_env(
        :bilimbi_base_database,
        PlatformBaselineTestRepo,
        platform_repo_options
      )

      on_exit(fn ->
        PlatformBaselineFailureDiagnostics.capture(context, :cleanup, fn ->
          Application.delete_env(:bilimbi_base_database, PlatformBaselineTestRepo)
        end)
      end)

      start_supervised!(PlatformBaselineTestRepo)
      assert PlatformBaselineTestRepo.config()[:pool_size] == 1

      %{
        env:
          [
            {"MIX_TEST_PARTITION", "_#{partition}"},
            {"BILIMBI_RUNTIME_SCHEMA_FIXTURE", "enabled"}
          ] ++ base_env
      }
    end)
  end

  @doc """
  Every installed migration as the umbrella root's runtime, the one the host
  tasks run in, discovers it.
  """
  def workspace_migration_entries(env) do
    {output, status} =
      System.cmd(
        System.find_executable("mix"),
        [
          "run",
          "--no-start",
          "-e",
          ~s[IO.puts("migration_entries:" <> Base.encode64(:erlang.term_to_binary(] <>
            ~s[Bilimbi.Core.Compatibility.migration_entries())))]
        ],
        cd: @workspace_root,
        env: [{"MIX_ENV", "test"} | env],
        stderr_to_stdout: true
      )

    assert status == 0, "mix run failed with status #{status}:\n#{output}"
    [encoded] = Regex.run(~r/^migration_entries:(\S+)$/m, output, capture: :all_but_first)
    encoded |> Base.decode64!() |> :erlang.binary_to_term()
  end

  @doc "Runs only the compatible baselines, in version order, from the umbrella root."
  def migrate_baselines_only!(env) do
    {output, status} =
      System.cmd(
        System.find_executable("mix"),
        [
          "run",
          "--no-start",
          "-e",
          "Bilimbi.Base.ModuleRegistry.complete_modules!(); " <>
            "{:ok, _, _} = Ecto.Migrator.with_repo(Bilimbi.Base.Repo, " <>
            "&Bilimbi.Core.Compatibility.migrate_baseline(&1, log: false))"
        ],
        cd: @workspace_root,
        env: [{"MIX_ENV", "test"} | env],
        stderr_to_stdout: true
      )

    PlatformBaselineFailureDiagnostics.record_nested_mix(
      "run",
      ["migrate_baseline"],
      status,
      output
    )

    assert status == 0, "baseline-only migrate failed with status #{status}:\n#{output}"
  end

  @doc "Runs a Mix task and returns its output, failing the test on a non-zero status."
  def run_mix!(task, args, env) do
    case run_mix(task, args, env) do
      {output, 0} ->
        output

      {output, status} ->
        flunk("mix #{task} failed with status #{status}:\n#{output}")
    end
  end

  @doc "Runs a Mix task: a host task from the umbrella root, anything else from this package."
  def run_mix(task, args, env) do
    {output, status} =
      System.cmd(
        System.find_executable("mix"),
        [task | args],
        cd: if(task in @host_tasks, do: @workspace_root, else: @package_root),
        env: [{"MIX_ENV", "test"} | env],
        stderr_to_stdout: true
      )

    PlatformBaselineFailureDiagnostics.record_nested_mix(task, args, status, output)
    {output, status}
  end

  @doc "Asserts the runtime refuses to boot on the named missing boundary."
  def assert_runtime_start_fails!(env, boundary) do
    {output, status} = run_mix("app.start", [], env)

    assert status != 0

    case boundary do
      :queue ->
        assert output =~ "Oban migrations have not been run"

      :employee ->
        assert output =~ "required runtime schema is missing: employee_types_system_company_check"
    end
  end

  @doc "The versions Bilimbi's ledger records in the throwaway database."
  def recorded_versions do
    SQL.query!(
      PlatformBaselineTestRepo,
      "SELECT version FROM bilimbi_schema_migrations ORDER BY version",
      []
    ).rows
    |> Enum.map(fn [version] -> version end)
  end

  @doc "How many steps `bilimbi.rollback` needs to reach and undo the given migration module."
  def rollback_step_to(entries, module) do
    entries
    |> Enum.reverse()
    |> Enum.find_index(fn {_version, migration_module, _disposition} ->
      migration_module == module
    end)
    |> case do
      nil -> raise ArgumentError, "unknown migration module: #{inspect(module)}"
      index -> index + 1
    end
  end

  @doc "The relation's name when it exists in the throwaway database, otherwise nil."
  def relation(table) do
    [[relation]] =
      SQL.query!(PlatformBaselineTestRepo, "SELECT to_regclass($1)::text", [table]).rows

    relation
  end

  @doc "Oban's migrated version in the throwaway database."
  def oban_migrated_version do
    Oban.Migrations.Postgres.migrated_version(repo: PlatformBaselineTestRepo)
  end

  @doc "Creates Laravel's three queue tables with one sentinel row each."
  def install_legacy_queue_sentinels! do
    for table <- ~w(jobs job_batches failed_jobs) do
      SQL.query!(
        PlatformBaselineTestRepo,
        "CREATE TABLE #{table} (id bigint PRIMARY KEY, payload text NOT NULL)",
        []
      )

      SQL.query!(
        PlatformBaselineTestRepo,
        "INSERT INTO #{table} (id, payload) VALUES (1, $1)",
        ["legacy-#{table}-payload"]
      )
    end
  end

  @doc "Asserts the three sentinel rows survived untouched."
  def assert_legacy_queue_sentinels_unchanged! do
    for table <- ~w(jobs job_batches failed_jobs) do
      expected_payload = "legacy-#{table}-payload"

      assert [[1, ^expected_payload]] =
               SQL.query!(
                 PlatformBaselineTestRepo,
                 "SELECT id, payload FROM #{table}",
                 []
               ).rows
    end
  end
end
