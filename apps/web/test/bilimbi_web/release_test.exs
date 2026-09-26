defmodule BilimbiWeb.ReleaseTest do
  # Mutates application environment that other tests read.
  use ExUnit.Case, async: false

  alias Bilimbi.Base.ModuleRegistry
  alias BilimbiWeb.Release

  describe "an incomplete graph" do
    setup do
      modules = ModuleRegistry.complete_modules!()

      on_exit(fn ->
        for module <- modules do
          Application.put_env(module.otp_app, :bilimbi_module, Map.delete(module, :path))
        end
      end)

      for module <- modules do
        descriptor = Application.fetch_env!(module.otp_app, :bilimbi_module)

        Application.put_env(
          module.otp_app,
          :bilimbi_module,
          %{descriptor | graph_module_ids: descriptor.graph_module_ids ++ ["domain/unmounted"]}
        )
      end

      :ok
    end

    test "migrate refuses it before touching the database" do
      assert_raise ArgumentError, ~r/cannot see installed modules domain\/unmounted/, fn ->
        Release.migrate()
      end
    end

    test "seed refuses it before starting workers or touching the database" do
      queues = Application.get_env(:bilimbi_base_queue, :queues)

      assert_raise ArgumentError, ~r/cannot see installed modules domain\/unmounted/, fn ->
        Release.seed()
      end

      assert Application.get_env(:bilimbi_base_queue, :queues) == queues
    end
  end

  describe "seed" do
    setup do
      env =
        for {app, key} <- [
              bilimbi_base_queue: :queues,
              bilimbi_base_queue: :plugins,
              bilimbi_base_schedule: :scheduler_enabled
            ],
            do: {app, key, Application.fetch_env(app, key)}

      on_exit(fn ->
        for {app, key, value} <- env do
          case value do
            {:ok, value} -> Application.put_env(app, key, value)
            :error -> Application.delete_env(app, key)
          end
        end
      end)
    end

    test "disables job processing and the scheduler" do
      Release.disable_workers()

      config = Bilimbi.Base.Queue.oban_config()
      assert config[:queues] == []
      assert config[:plugins] == []
      assert Application.get_env(:bilimbi_base_schedule, :scheduler_enabled) == false
    end

    test "starts every module application but not the host that owns the endpoint" do
      started = closure(Release.seed_applications(), MapSet.new())

      refute MapSet.member?(started, :web)
      assert Application.get_application(BilimbiWeb.Endpoint) == :web

      for module <- ModuleRegistry.complete_modules!() do
        assert MapSet.member?(started, module.otp_app)
      end
    end
  end

  defp closure(apps, seen) do
    Enum.reduce(apps, seen, fn app, seen ->
      if MapSet.member?(seen, app) do
        seen
      else
        closure(List.wrap(Application.spec(app, :applications)), MapSet.put(seen, app))
      end
    end)
  end
end
