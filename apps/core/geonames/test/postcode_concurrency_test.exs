defmodule Bilimbi.Core.Geonames.PostcodeConcurrencyTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 60_000

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Geonames
  alias Bilimbi.Core.Geonames.Admin1
  alias Bilimbi.Core.Geonames.Country
  alias Bilimbi.Core.Geonames.Importer
  alias Bilimbi.Core.Geonames.Migrations.CreateCompatibilityBaseline
  alias Bilimbi.Core.Geonames.Migrations.CreatePostcodeOverrides
  alias Bilimbi.Core.Geonames.Postcode
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    Code.require_file(
      Path.expand(
        "../priv/repo/migrations/20260812103801_create_core_geonames_compatibility_baseline.exs",
        __DIR__
      )
    )

    Code.require_file(
      Path.expand(
        "../priv/repo/migrations/20260820143500_create_geonames_postcode_overrides.exs",
        __DIR__
      )
    )

    unique = System.unique_integer([:positive])
    database = "bilimbi_geonames_concurrency_#{unique}"
    quoted_database = SchemaVerifier.quote_identifier!(database)

    Sandbox.unboxed_run(Repo, fn ->
      SQL.query!(Repo, "CREATE DATABASE #{quoted_database}", [])
    end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        SQL.query!(Repo, "DROP DATABASE IF EXISTS #{quoted_database} WITH (FORCE)", [])
      end)
    end)

    original_repo_options = Application.fetch_env!(:bilimbi_base_database, Repo)

    concurrent_repo_options =
      Repo.config()
      |> Keyword.put(:database, database)
      |> Keyword.put(:pool, DBConnection.ConnectionPool)
      |> Keyword.put(:pool_size, 2)

    Application.put_env(:bilimbi_base_database, Repo, concurrent_repo_options)
    on_exit(fn -> Application.put_env(:bilimbi_base_database, Repo, original_repo_options) end)

    assert Application.fetch_env!(:bilimbi_base_database, Repo)[:pool] ==
             DBConnection.ConnectionPool

    repo_names =
      for role <- [:observer, :locker, :importer, :updater], into: %{} do
        repo_pid =
          start_supervised!(
            {Repo,
             name: nil,
             database: database,
             pool: DBConnection.ConnectionPool,
             pool_size: if(role == :observer, do: 2, else: 1)},
            id: {Repo, role, unique}
          )

        {role, repo_pid}
      end

    assert Ecto.Repo.Registry.lookup(repo_names.observer).opts[:pool] ==
             DBConnection.ConnectionPool

    with_repo(repo_names.observer, fn ->
      Ecto.Migrator.up(Repo, 20_260_812_103_801, CreateCompatibilityBaseline, log: false)
      Ecto.Migrator.up(Repo, 20_260_820_143_500, CreatePostcodeOverrides, log: false)
    end)

    supervisor = start_supervised!(Task.Supervisor)

    %{repo_names: repo_names, supervisor: supervisor}
  end

  test "cross-country import and edit use one lock order", %{
    repo_names: repos,
    supervisor: supervisor
  } do
    parent = self()

    directory =
      Path.join(System.tmp_dir!(), "bilimbi-geonames-locking-#{System.unique_integer()}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    postcode_path =
      write!(directory, "MY.txt", postcode_file("50000", "Kuala Lumpur"))

    {moved, override_id} =
      with_repo(repos.observer, fn ->
        assert Repo.get_dynamic_repo() == repos.observer

        Repo.insert!(%Country{
          iso: "MY",
          iso3: "MYS",
          iso_numeric: "458",
          country: "Malaysia",
          population: 0,
          continent: "AS"
        })

        Repo.insert!(%Country{
          iso: "US",
          iso3: "USA",
          iso_numeric: "840",
          country: "United States",
          population: 0,
          continent: "NA"
        })

        Repo.insert!(%Admin1{code: "US.CA", name: "California"})

        source =
          Repo.insert!(%Postcode{
            country_iso: "MY",
            postcode: "50000",
            place_name: "Kuala Lumpur"
          })

        revision =
          Geonames.page_postcodes(%{search: source.postcode}).entries
          |> hd()
          |> Map.fetch!(:revision)

        assert {:ok, moved} =
                 Geonames.update_postcode(source.id, revision, %{
                   country_iso: "US",
                   postcode: "95000",
                   place_name: "Local California",
                   admin1_code: "CA"
                 })

        [[override_id]] = sql_query!("SELECT id FROM geonames_postcode_overrides", []).rows

        {moved, override_id}
      end)

    locker =
      Task.Supervisor.async_nolink(supervisor, fn ->
        with_repo(repos.locker, fn ->
          Repo.transaction(fn ->
            sql_query!(
              "SELECT id FROM geonames_postcode_overrides WHERE id = $1 FOR UPDATE",
              [override_id]
            )

            send(parent, {:override_locked, self()})

            receive do
              :release_override -> :ok
            end
          end)
        end)
      end)

    assert_receive {:override_locked, locker_pid}

    importer =
      Task.Supervisor.async_nolink(supervisor, fn ->
        with_repo(repos.importer, fn ->
          send(parent, {:importer_backend, backend_pid()})
          Importer.postcodes("MY", postcode_path, repo: Repo)
        end)
      end)

    assert_receive {:importer_backend, importer_backend}
    assert_blocked(repos.observer, importer_backend)

    updater =
      Task.Supervisor.async_nolink(supervisor, fn ->
        with_repo(repos.updater, fn ->
          send(parent, {:updater_backend, backend_pid()})

          Geonames.update_postcode(moved.id, moved.revision, %{
            country_iso: "US",
            postcode: "95000",
            place_name: "Concurrent edit",
            admin1_code: "CA"
          })
        end)
      end)

    assert_receive {:updater_backend, updater_backend}
    assert_blocked(repos.observer, updater_backend)
    send(locker_pid, :release_override)

    assert {:ok, {:ok, _transaction_result}} = Task.yield(locker, 5_000)
    assert {:ok, {:ok, %{imported: 1}}} = Task.yield(importer, 5_000)

    assert {:ok, update_result} = Task.yield(updater, 5_000)

    assert match?({:ok, _postcode}, update_result) or
             update_result in [{:error, :stale}, {:error, :not_found}]

    expected_place =
      case update_result do
        {:ok, _postcode} -> "Concurrent edit"
        _other -> "Local California"
      end

    with_repo(repos.observer, fn ->
      assert [[1]] = sql_query!("SELECT count(*) FROM geonames_postcode_overrides", []).rows

      assert [[applied_id, postcode_id, ^expected_place]] =
               sql_query!(
                 """
                 SELECT override.applied_postcode_id, postcode.id, postcode.place_name
                 FROM geonames_postcode_overrides AS override
                 JOIN geonames_postcodes AS postcode
                   ON postcode.id = override.applied_postcode_id
                 """,
                 []
               ).rows

      assert applied_id == postcode_id
    end)
  end

  test "concurrent first edits return one stale result instead of raising", %{
    repo_names: repos,
    supervisor: supervisor
  } do
    parent = self()

    {source, revision} =
      with_repo(repos.observer, fn ->
        Repo.insert!(%Country{
          iso: "MY",
          iso3: "MYS",
          iso_numeric: "458",
          country: "Malaysia",
          population: 0,
          continent: "AS"
        })

        source =
          Repo.insert!(%Postcode{
            country_iso: "MY",
            postcode: "50000",
            place_name: "Kuala Lumpur"
          })

        revision =
          Geonames.page_postcodes(%{search: source.postcode}).entries
          |> hd()
          |> Map.fetch!(:revision)

        {source, revision}
      end)

    locker =
      Task.Supervisor.async_nolink(supervisor, fn ->
        with_repo(repos.locker, fn ->
          Repo.transaction(fn ->
            sql_query!("SELECT id FROM geonames_postcodes WHERE id = $1 FOR UPDATE", [source.id])
            send(parent, {:postcode_locked, self()})

            receive do
              :release_postcode -> :ok
            end
          end)
        end)
      end)

    assert_receive {:postcode_locked, locker_pid}

    first =
      start_editor(supervisor, repos.importer, parent, :first, source.id, revision, "Editor one")

    assert_receive {:editor_backend, :first, first_backend}
    assert_blocked(repos.observer, first_backend)

    second =
      start_editor(supervisor, repos.updater, parent, :second, source.id, revision, "Editor two")

    assert_receive {:editor_backend, :second, second_backend}
    assert_blocked(repos.observer, second_backend)
    send(locker_pid, :release_postcode)

    assert {:ok, {:ok, _transaction_result}} = Task.yield(locker, 5_000)
    assert {:ok, first_result} = Task.yield(first, 5_000)
    assert {:ok, second_result} = Task.yield(second, 5_000)

    results = [first_result, second_result]
    assert Enum.count(results, &match?({:ok, _postcode}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :stale})) == 1

    with_repo(repos.observer, fn ->
      assert [[1]] = sql_query!("SELECT count(*) FROM geonames_postcode_overrides", []).rows
    end)
  end

  test "non-public prefix rollback refuses active override provenance", %{repo_names: repos} do
    prefix = "geonames_override_prefix"

    with_repo(repos.observer, fn ->
      sql_query!("CREATE SCHEMA \"#{prefix}\"", [])

      Ecto.Migrator.up(Repo, 20_260_812_103_801, CreateCompatibilityBaseline,
        log: false,
        prefix: prefix
      )

      Ecto.Migrator.up(Repo, 20_260_820_143_500, CreatePostcodeOverrides,
        log: false,
        prefix: prefix
      )

      sql_query!(
        """
        INSERT INTO "#{prefix}".geonames_countries
          (iso, iso3, iso_numeric, country, population, continent)
        VALUES ('MY', 'MYS', '458', 'Malaysia', 0, 'AS')
        """,
        []
      )

      sql_query!(
        """
        WITH materialized AS (
          INSERT INTO "#{prefix}".geonames_postcodes (country_iso, postcode, place_name)
          VALUES ('MY', '50000', 'Prefixed correction')
          RETURNING id
        )
        INSERT INTO "#{prefix}".geonames_postcode_overrides
          (applied_postcode_id, country_iso, postcode, place_name, lock_version,
           created_at, updated_at)
        SELECT id, 'MY', '50000', 'Prefixed correction', 1,
               timezone('UTC', now()), timezone('UTC', now())
        FROM materialized
        """,
        []
      )

      assert [[0]] = sql_query!("SELECT count(*) FROM geonames_postcode_overrides", []).rows

      assert_raise Postgrex.Error,
                   ~r/cannot roll back postcode overrides while operator corrections exist/,
                   fn ->
                     Ecto.Migrator.down(
                       Repo,
                       20_260_820_143_500,
                       CreatePostcodeOverrides,
                       log: false,
                       prefix: prefix
                     )
                   end

      expected_relation = "#{prefix}.geonames_postcode_overrides"

      assert [[^expected_relation]] =
               sql_query!("SELECT to_regclass($1)::text", [expected_relation]).rows
    end)
  end

  defp assert_blocked(observer, backend_pid) do
    deadline = System.monotonic_time(:millisecond) + 5_000
    wait_until_blocked(observer, backend_pid, deadline)
  end

  defp wait_until_blocked(observer, backend_pid, deadline) do
    blocked? =
      with_repo(observer, fn ->
        case sql_query!("SELECT pg_blocking_pids($1)", [backend_pid]).rows do
          [[blockers]] -> blockers != []
        end
      end)

    cond do
      blocked? ->
        :ok

      System.monotonic_time(:millisecond) < deadline ->
        :erlang.yield()
        wait_until_blocked(observer, backend_pid, deadline)

      true ->
        flunk("database backend #{backend_pid} did not enter a lock wait")
    end
  end

  defp backend_pid do
    [[backend_pid]] = sql_query!("SELECT pg_backend_pid()", []).rows
    backend_pid
  end

  defp start_editor(supervisor, repo, parent, label, postcode_id, revision, place_name) do
    Task.Supervisor.async_nolink(supervisor, fn ->
      with_repo(repo, fn ->
        send(parent, {:editor_backend, label, backend_pid()})
        Geonames.update_postcode(postcode_id, revision, %{place_name: place_name})
      end)
    end)
  end

  defp sql_query!(statement, params) do
    SQL.query!(Repo.get_dynamic_repo(), statement, params)
  end

  defp with_repo(repo_name, fun) do
    previous_repo = Repo.put_dynamic_repo(repo_name)

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous_repo)
    end
  end

  defp postcode_file(postcode, place_name) do
    "MY\t#{postcode}\t#{place_name}\tAdmin1\t14\t\t\t\t\t3.139\t101.6869\t4\n"
  end

  defp write!(directory, filename, contents) do
    path = Path.join(directory, filename)
    File.write!(path, contents)
    path
  end
end
