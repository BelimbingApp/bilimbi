defmodule Bilimbi.Base.Queue.PrefixTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Queue.JobPage
  alias Bilimbi.Base.Queue.Migrations.CreateObanRuntime
  alias Bilimbi.Base.Queue.TestWorkers.Success
  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  @application :bilimbi_base_queue

  test "configured non-public prefix is shared by migration, runtime, and direct reads" do
    schema =
      "queue_prefix_#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}"

    name = Module.concat(__MODULE__, "Oban#{System.unique_integer([:positive, :monotonic])}")
    original_name = Application.get_env(@application, :name)
    original_prefix = Application.get_env(@application, :prefix)
    original_dynamic_repo = Application.get_env(@application, :get_dynamic_repo)
    repo_name = start_isolated_repo!()
    previous_dynamic_repo = Repo.put_dynamic_repo(repo_name)
    quoted_schema = SchemaVerifier.quote_identifier!(schema)

    SQL.query!(repo_name, "CREATE SCHEMA #{quoted_schema}", [])

    Ecto.Migrator.run(
      Repo,
      [{20_260_820_130_000, CreateObanRuntime}],
      :up,
      all: true,
      log: false,
      prefix: schema,
      dynamic_repo: repo_name
    )

    Application.put_env(@application, :name, name)
    Application.put_env(@application, :prefix, schema)
    Application.put_env(@application, :get_dynamic_repo, fn -> repo_name end)

    try do
      start_supervised!({Oban, Queue.oban_config()})
      public_count = Repo.aggregate(Oban.Job, :count, :id)

      assert {:ok, reference} = Queue.enqueue(Success, %{"value" => 9})
      assert {:ok, %JobPage{total: 1}} = Queue.list_jobs()
      assert Queue.diagnostics().backlog == 1

      prefixed_jobs = Ecto.Query.put_query_prefix(Oban.Job, schema)
      assert Repo.aggregate(prefixed_jobs, :count, :id) == 1
      assert Repo.aggregate(from(job in Oban.Job), :count, :id) == public_count
      assert :ok = Queue.cancel(reference.id)
    after
      _ = stop_supervised(name)
      restore_env(:name, original_name)
      restore_env(:prefix, original_prefix)
      restore_env(:get_dynamic_repo, original_dynamic_repo)
      Repo.put_dynamic_repo(repo_name)
      SQL.query!(repo_name, "DROP SCHEMA #{quoted_schema} CASCADE", [])
      Repo.put_dynamic_repo(previous_dynamic_repo)
    end
  end

  defp start_isolated_repo! do
    name = Module.concat(__MODULE__, "Repo#{System.unique_integer([:positive, :monotonic])}")

    options =
      Repo.config()
      |> Keyword.put(:name, name)
      |> Keyword.put(:pool_size, 4)

    {Repo, options}
    |> Supervisor.child_spec(id: name)
    |> start_supervised!()

    previous_dynamic_repo = Repo.put_dynamic_repo(name)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Repo.put_dynamic_repo(previous_dynamic_repo)
    name
  end

  defp restore_env(key, nil), do: Application.delete_env(@application, key)
  defp restore_env(key, value), do: Application.put_env(@application, key, value)
end
