# The real tasks live in other packages (core/compatibility, Web). This
# package's VM has neither, so these stand-ins record what the server task
# dispatches and in which order; Mix.Task.run resolves them by name exactly
# as it resolves the real ones from the umbrella root.
defmodule Mix.Tasks.Bilimbi.Migrate do
  @moduledoc false
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    send(
      Application.fetch_env!(:bilimbi_base_module_registry, :server_test_pid),
      {:migrate, args}
    )
  end
end

defmodule Mix.Tasks.Phx.Server do
  @moduledoc false
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    send(Application.fetch_env!(:bilimbi_base_module_registry, :server_test_pid), {:server, args})
  end
end

defmodule Mix.Tasks.Bilimbi.Dev.Seed do
  @moduledoc false
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    send(Application.fetch_env!(:bilimbi_base_module_registry, :server_test_pid), {:seed, args})
  end
end

defmodule Mix.Tasks.Bilimbi.ServerStartTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Bilimbi.Server

  setup do
    Application.put_env(:bilimbi_base_module_registry, :server_test_pid, self())
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(shell)
      Application.delete_env(:bilimbi_base_module_registry, :server_test_pid)
    end)

    reenable_tasks()
    :ok
  end

  defp reenable_tasks do
    Enum.each(["bilimbi.migrate", "phx.server", "bilimbi.dev.seed"], &Mix.Task.reenable/1)
  end

  test "development migrates before Phoenix starts and seeds once it is up" do
    Server.start(["--open"], :dev)

    # Messages arrive in dispatch order: migrate, server, seed.
    assert_received {:migrate, []}
    assert_received {:server, ["--open"]}
    assert_received {:seed, ["--at-startup"]}
    assert_received {:mix_shell, :info, ["Migrating the development database" <> _]}
    refute_received {:seed, _}
  end

  test "--no-migrate starts Phoenix alone and is not passed on" do
    Server.start(["--no-migrate", "--open"], :dev)

    refute_received {:migrate, _}
    assert_received {:server, ["--open"]}
    refute_received {:seed, _}
  end

  test "other environments neither migrate nor seed at start-up" do
    for env <- [:test, :prod] do
      reenable_tasks()
      Server.start([], env)

      refute_received {:migrate, _}
      assert_received {:server, []}
      refute_received {:seed, _}
    end
  end
end
