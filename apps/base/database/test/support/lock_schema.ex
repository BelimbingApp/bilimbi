defmodule Bilimbi.Base.Database.LockSchema do
  @moduledoc """
  The two-connection harness for proving row-lock behaviour.

  A temporary table is private to its connection, so a test that needs one
  connection to wait on another's row lock cannot use the sandbox. It uses a
  real schema instead, each connection checked out with `sandbox: false` and
  pointed at it with `on_schema!/2`. The tables come from the owning module's
  fixtures called with `persistent: true`, never from DDL restated in the test
  (`TestTables` says how a fixture honours the option).

      setup do
        schema = LockSchema.create!("company_live_lock")
        LockSchema.on_schema!(schema, fn -> TenancyFixtures.create_tenants_table!(persistent: true) end)
        %{schema: schema}
      end

  Use `import Bilimbi.Base.Database.LockSchema`. The test module is
  `async: false`: it holds real locks and a connection beyond the sandbox pool.
  """

  import ExUnit.Assertions, only: [flunk: 1]
  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  # A holder waiting for the test to release it must not hang the suite.
  @message_timeout 5_000
  # A lock wait is the state of another PostgreSQL backend, and no message
  # announces it, so it is observed by polling `pg_stat_activity`. The bound
  # is a deadline, not a count of naps.
  @lock_wait_timeout 10_000
  @lock_wait_interval 10

  @doc """
  Creates an empty schema named `label` plus a random suffix, drops it when
  the test exits, and returns its name. The calling process is left checked
  out of the sandbox.
  """
  def create!(label) when is_binary(label) do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    schema = "#{label}_#{:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)}"
    SQL.query!(Repo, "CREATE SCHEMA #{quote_ident(schema)}", [])

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      SQL.query!(Repo, "DROP SCHEMA IF EXISTS #{quote_ident(schema)} CASCADE", [])
    end)

    schema
  end

  @doc "Runs `fun` on this connection with `schema` first on the search path."
  def on_schema!(schema, fun) when is_function(fun, 0) do
    SQL.query!(Repo, "SET search_path TO #{quote_ident(schema)}", [])

    try do
      fun.()
    after
      SQL.query!(Repo, "SET search_path TO public", [])
    end
  end

  @doc "Checks out a connection of its own, then `on_schema!/2`. For a spawned task."
  def checkout_on_schema!(schema, fun) when is_function(fun, 0) do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    on_schema!(schema, fun)
  end

  @doc "This connection's PostgreSQL backend, for the test to wait on."
  def backend_pid! do
    %{rows: [[backend_pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
    backend_pid
  end

  @doc """
  Blocks until `backend_pid` is waiting on a row lock, and fails the test when
  it does not within the bound. Call it before releasing the holder, so the
  contender is known to be queued behind it.
  """
  def await_row_lock!(backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @lock_wait_timeout
    await_row_lock!(backend_pid, deadline)
  end

  defp await_row_lock!(backend_pid, deadline) do
    %{rows: rows} =
      SQL.query!(Repo, "SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [
        backend_pid
      ])

    cond do
      rows == [["Lock"]] ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk(
          "backend #{backend_pid} never waited on a PostgreSQL row lock (saw #{inspect(rows)})"
        )

      true ->
        receive do
        after
          @lock_wait_interval -> await_row_lock!(backend_pid, deadline)
        end
    end
  end

  @doc """
  Inside a holder's transaction: waits for the test's go-ahead message, and
  rolls the holder back when it never comes.
  """
  def await_message!(message) do
    receive do
      ^message -> :ok
    after
      @message_timeout -> Repo.rollback({:timeout, message})
    end
  end

  defp quote_ident(name) when is_binary(name) do
    if name =~ ~r/^[a-z][a-z0-9_]*$/ do
      name
    else
      raise ArgumentError, "refusing to interpolate #{inspect(name)} as an identifier"
    end
  end
end
