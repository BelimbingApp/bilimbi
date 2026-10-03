defmodule Bilimbi.Base.SystemTest do
  @moduledoc """
  The screen's promise is that every row is either a real fact or an honest
  "Unavailable" -- never a crash, and never an invented value.
  """

  use ExUnit.Case, async: false

  # Aliased, not imported as `System`: an `alias Bilimbi.Base.System` shadows
  # Elixir's own `System`, and these assertions compare against it.
  alias Bilimbi.Base.System, as: SystemInfo
  alias Bilimbi.Base.System.Contributions

  describe "fact sections" do
    test "every section returns labelled facts and nothing raises" do
      for {section, facts} <- [
            application: SystemInfo.application(),
            runtime: SystemInfo.runtime(),
            server: SystemInfo.server(),
            health: SystemInfo.health()
          ] do
        assert facts != [], "#{section} returned no facts"

        for fact <- facts do
          assert is_binary(fact.label) and fact.label != ""

          assert is_binary(fact.value) or fact.value == :unavailable,
                 "#{section}/#{fact.label} was #{inspect(fact.value)}"
        end
      end
    end

    test "application facts use the configured runtime environment and real locale settings" do
      previous = Application.get_env(:bilimbi_base_ui, :mix_env)
      Application.put_env(:bilimbi_base_ui, :mix_env, :test)

      on_exit(fn ->
        if previous do
          Application.put_env(:bilimbi_base_ui, :mix_env, previous)
        else
          Application.delete_env(:bilimbi_base_ui, :mix_env)
        end
      end)

      facts = Map.new(SystemInfo.application(), &{&1.label, &1.value})

      assert facts["Environment"] == "test"
      assert facts["Timezone"] == Application.get_env(:bilimbi_base_ui, :timezone, "Etc/UTC")
      assert facts["Locale"] == Bilimbi.Base.Locale.locale(nil)
    end

    test "debug mode follows endpoint configuration independently of environment" do
      previous_env = Application.fetch_env(:bilimbi_base_ui, :mix_env)
      previous_endpoint = Application.fetch_env(:web, BilimbiWeb.Endpoint)

      on_exit(fn ->
        for {app, key, previous} <- [
              {:bilimbi_base_ui, :mix_env, previous_env},
              {:web, BilimbiWeb.Endpoint, previous_endpoint}
            ] do
          case previous do
            {:ok, value} -> Application.put_env(app, key, value)
            :error -> Application.delete_env(app, key)
          end
        end
      end)

      for environment <- [:dev, :test, :prod],
          {config, expected} <- [
            {[debug_errors: true], "Enabled"},
            {[debug_errors: false], "Disabled"},
            {[], "Disabled"}
          ] do
        Application.put_env(:bilimbi_base_ui, :mix_env, environment)
        Application.put_env(:web, BilimbiWeb.Endpoint, config)
        facts = Map.new(SystemInfo.application(), &{&1.label, &1.value})

        assert facts["Environment"] == to_string(environment)
        assert facts["Debug Mode"] == expected
      end

      Application.delete_env(:web, BilimbiWeb.Endpoint)
      facts = Map.new(SystemInfo.application(), &{&1.label, &1.value})
      assert facts["Debug Mode"] == "Disabled"
    end

    test "runtime reports the real BEAM, not a hard-coded string" do
      facts = Map.new(SystemInfo.runtime(), &{&1.label, &1.value})

      # Derived from the running VM rather than compared to a literal, so this
      # cannot pass against a stubbed value and cannot break on an upgrade.
      assert facts["Elixir"] == System.version()
      assert facts["OTP Release"] == System.otp_release()
      assert facts["Memory In Use"] =~ ~r/^\d+\.\d [KMGT]?B$/
      assert facts["Processes"] =~ ~r/^\d+ of \d+$/
    end

    test "the queue reports the real supervised manual-test availability" do
      health = Map.new(SystemInfo.health(), &{&1.label, &1.value})

      # Manual mode starts no consumers, but it does supervise the migrated
      # runtime and keeps the operational probe truthful.
      assert health["Queue"] == "Available (0 pending, 0 retryable, 0 discarded)"
      assert health["Performance"] in ["Unavailable", "Available (0 pending, 0 dropped)"]
    end

    test "loaded applications carry versions and are sorted" do
      applications = SystemInfo.applications()

      assert length(applications) > 10
      assert Enum.all?(applications, &(&1.version != ""))
      assert applications == Enum.sort_by(applications, & &1.name)

      names = Enum.map(applications, & &1.name)
      assert "elixir" in names
    end
  end

  test "publishes one capability-gated localization destination" do
    contributions = Contributions.contributions()

    assert %{
             route: "/system/localization",
             capability: "admin.system.localization.manage"
           } = Enum.find(contributions.menu, &(&1.id == "admin.system.localization"))

    assert "admin.system.localization.manage" in contributions.authz.capabilities

    refute "admin.system.localization.manage" in contributions.authz.roles["system_viewer"].capabilities
  end
end
