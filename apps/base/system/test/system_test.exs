defmodule Bilimbi.Base.SystemTest do
  @moduledoc """
  The screen's promise is that every row is either a real fact or an honest
  "Unavailable" -- never a crash, and never an invented value.
  """

  use ExUnit.Case, async: true

  # Aliased, not imported as `System`: an `alias Bilimbi.Base.System` shadows
  # Elixir's own `System`, and these assertions compare against it.
  alias Bilimbi.Base.System, as: SystemInfo

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

    test "runtime reports the real BEAM, not a hard-coded string" do
      facts = Map.new(SystemInfo.runtime(), &{&1.label, &1.value})

      # Derived from the running VM rather than compared to a literal, so this
      # cannot pass against a stubbed value and cannot break on an upgrade.
      assert facts["Elixir"] == System.version()
      assert facts["OTP Release"] == System.otp_release()
      assert facts["Memory In Use"] =~ ~r/^\d+\.\d [KMGT]?B$/
      assert facts["Processes"] =~ ~r/^\d+ of \d+$/
    end

    test "the queue reports the real isolated-test availability" do
      health = Map.new(SystemInfo.health(), &{&1.label, &1.value})

      # Base Queue intentionally starts no consumers in an isolated package
      # test. The real probe must therefore report unavailable, not a stubbed
      # healthy value.
      assert health["Queue"] == :unavailable
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
end
