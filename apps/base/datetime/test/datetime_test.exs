defmodule Bilimbi.Base.DateTimeTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.DateTime, as: Policy
  alias Bilimbi.Base.DateTime.Contributions
  alias Bilimbi.Base.DateTime.Display
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.ContributionValidator
  alias Bilimbi.Base.Settings.Scope
  alias Bilimbi.Base.Settings.TestFixtures

  setup_all do
    settings =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "base/datetime"},
          payload: Contributions.contributions().settings
        },
        %{
          descriptor: %{id: "base/locale"},
          payload: Bilimbi.Base.Locale.Contributions.contributions().settings
        }
      ])

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "base-datetime-test",
      consumers: %{settings: settings}
    })

    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  setup tags do
    unless tags[:without_settings_table], do: TestFixtures.create_settings_table!()
    :ok
  end

  defp user_scope(user_id \\ 91), do: Scope.user(user_id, 73, 41)
  defp company_scope, do: Scope.company(73, 41)

  test "declares both policy definitions" do
    definitions = Contributions.contributions().settings.definitions

    assert %{scopes: [:tenant, :company], default: "UTC"} =
             Map.new(definitions["localization.timezone"])

    assert %{scopes: [:user], default: "company"} = Map.new(definitions["ui.timezone.mode"])
  end

  test "mode defaults to :company and persists only canonical values" do
    scope = user_scope()

    assert Policy.mode(scope) == :company
    refute Policy.mode_overridden?(scope)

    assert {:ok, :local} = Policy.put_mode(scope, "local")
    assert Policy.mode(scope) == :local
    assert Policy.mode_overridden?(scope)

    assert {:ok, :utc} = Policy.put_mode(scope, :utc)
    assert Policy.mode(scope) == :utc

    assert {:error, :invalid_mode} = Policy.put_mode(scope, "sydney")
    assert {:error, :invalid_mode} = Policy.put_mode(scope, "COMPANY")
    assert {:error, :invalid_mode} = Policy.put_mode(scope, 1)
    assert Policy.mode(scope) == :utc

    assert :ok = Policy.delete_mode(scope)
    assert Policy.mode(scope) == :company
  end

  test "a forged stored value resolves to the default, never to an arbitrary atom" do
    scope = user_scope()
    assert {:ok, _} = Settings.put("ui.timezone.mode", "company", scope)

    Repo.query!("UPDATE base_settings SET value = to_json('galactic'::text)")
    assert Policy.mode(scope) == :company
  end

  test "modes stay isolated between accounts" do
    assert {:ok, :utc} = Policy.put_mode(user_scope(91), :utc)
    assert {:ok, :local} = Policy.put_mode(user_scope(92), :local)

    assert Policy.mode(user_scope(91)) == :utc
    assert Policy.mode(user_scope(92)) == :local
  end

  test "validates IANA identifiers against the real database, not the UTC-only stdlib" do
    assert Policy.valid_timezone?("Asia/Kuala_Lumpur")
    assert Policy.valid_timezone?("Europe/Berlin")
    assert Policy.valid_timezone?("UTC")
    refute Policy.valid_timezone?("Mars/Olympus_Mons")
    refute Policy.valid_timezone?("")
    refute Policy.valid_timezone?(nil)

    zones = Policy.timezones()
    assert "Asia/Kuala_Lumpur" in zones
    refute Enum.empty?(zones)
  end

  test "company timezone defaults to UTC and refuses to present an unconvertible value" do
    assert Policy.company_timezone(nil) == "UTC"
    assert Policy.company_timezone(company_scope()) == "UTC"

    assert {:ok, _} = Settings.put("localization.timezone", "Asia/Kuala_Lumpur", company_scope())
    assert Policy.company_timezone(company_scope()) == "Asia/Kuala_Lumpur"

    Repo.query!("UPDATE base_settings SET value = to_json('Atlantis/Sunken'::text)")
    assert Policy.company_timezone(company_scope()) == "UTC"
  end

  test "display resolves mode, company zone, locale, and the database" do
    assert %Display{mode: :local} = Policy.display(nil)

    assert {:ok, _} = Settings.put("localization.timezone", "Asia/Kuala_Lumpur", company_scope())

    display = Policy.display(user_scope(), company_scope())
    assert %Display{mode: :company, timezone: "Asia/Kuala_Lumpur", tz_db: db} = display
    assert db == TimeZoneInfo.TimeZoneDatabase
    assert is_binary(display.locale)

    assert {:ok, :utc} = Policy.put_mode(user_scope(), :utc)
    assert %Display{mode: :utc} = Policy.display(user_scope(), company_scope())
  end

  @tag :without_settings_table
  test "display returns defaults before the canonical Settings table exists" do
    assert %Display{mode: :company, timezone: "UTC"} =
             Policy.display(user_scope(), company_scope())
  end

  test "interprets compatible NaiveDateTime as UTC and shifts across DST boundaries" do
    # Europe/Berlin springs forward 2026-03-29 01:00Z (02:00 CET -> 03:00 CEST).
    before = ~N[2026-03-29 00:59:59]
    after_ = ~N[2026-03-29 01:00:00]

    assert {:ok, shifted_before} = Policy.shift(before, "Europe/Berlin")
    assert shifted_before.hour == 1
    assert shifted_before.zone_abbr == "CET"
    assert shifted_before.utc_offset + shifted_before.std_offset == 3600

    assert {:ok, shifted_after} = Policy.shift(after_, "Europe/Berlin")
    assert shifted_after.hour == 3
    assert shifted_after.zone_abbr == "CEST"
    assert shifted_after.utc_offset + shifted_after.std_offset == 7200

    assert {:ok, kl} = Policy.shift(~U[2026-01-01 16:30:00Z], "Asia/Kuala_Lumpur")
    assert {kl.day, kl.hour, kl.minute} == {2, 0, 30}

    assert {:error, _reason} = Policy.shift(~N[2026-01-01 00:00:00], "Mars/Olympus_Mons")
  end
end
