defmodule BilimbiWeb.SettingsLiveTest do
  @moduledoc """
  The operator settings page, end to end.

  `Bilimbi.Base.Settings.FormTest` owns the rules; this covers what a user can
  actually reach and see — that the page is generated from declared
  definitions, that inherited and set-here look different, and that clearing a
  field is visibly not the same as saving nothing.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @retention "authz.decision_log_retention_days"
  @input "settings[#{@retention}]"

  setup do
    UserFixtures.create_user_tables!()
    SettingsFixtures.create_settings_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  defp open(conn) do
    grant_capabilities!("base.settings.global.manage")
    conn |> log_in_as() |> live(~p"/system/settings")
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/system/settings")
  end

  test "redirects away when the actor lacks base.settings.global.manage", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/system/settings")
  end

  test "renders a field the module declared, not one the page hardcoded", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    # base/authz contributes this setting; base/settings renders it without
    # naming it. A module adding a setting to this group needs no UI change.
    assert has_element?(view, "#setting-authz-decision_log_retention_days")
    assert has_element?(view, "label", "Authorization log retention")
    assert has_element?(view, "#nav-admin-system-settings[aria-current='page']")
  end

  test "shows an unset value as inherited from its default", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    assert has_element?(view, "#setting-authz-decision_log_retention_days", "Inherited")
    refute has_element?(view, "#setting-authz-decision_log_retention_days", "Set here")
  end

  test "saving marks the field as set here", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view |> form("#settings-form", %{@input => "45"}) |> render_submit()

    assert Settings.get(@retention) == 45
    assert has_element?(view, "#setting-authz-decision_log_retention_days", "Set here")
    assert render(view) =~ "2 settings updated"
  end

  test "clearing a field says so, and the value returns to its default", %{conn: conn} do
    assert {:ok, 45} = Settings.put(@retention, 45)
    {:ok, view, _html} = open(conn)

    view |> form("#settings-form", %{@input => ""}) |> render_submit()

    # The distinction that matters: the value is back to 90 and the page says
    # an override was cleared, rather than reporting a save that looks empty.
    assert Settings.get(@retention) == 90
    refute Settings.overridden?(@retention)
    assert render(view) =~ "1 override cleared"
  end

  test "reports a rejected value against the field, and writes nothing", %{conn: conn} do
    assert {:ok, 45} = Settings.put(@retention, 45)
    {:ok, view, _html} = open(conn)

    view |> form("#settings-form", %{@input => "not-a-number"}) |> render_submit()

    assert render(view) =~ "Authorization log retention"
    assert render(view) =~ "must be a whole number"
    assert Settings.get(@retention) == 45
  end

  test "submitting the default value still creates an override", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view |> form("#settings-form", %{@input => "90"}) |> render_submit()

    # 90 is also the default, but typing it is a decision to pin it here rather
    # than keep inheriting. Belimbing writes in this case too; only an empty
    # field means "stop overriding". Asserted so nobody "optimises" the write
    # away and silently turns a pin into an inherit.
    assert Settings.overridden?(@retention)
    assert render(view) =~ "2 settings updated"
  end

  test "a submission that touches nothing reports no change", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    # No settings key at all: the form submitted nothing this page owns.
    view |> render_submit("save", %{})

    assert render(view) =~ "No changes to save."
  end

  test "restore defaults clears overrides and reports what it did", %{conn: conn} do
    assert {:ok, 45} = Settings.put(@retention, 45)
    {:ok, view, _html} = open(conn)

    view |> element("#settings-restore") |> render_click()

    refute Settings.overridden?(@retention)
    assert render(view) =~ "1 override cleared"
  end

  test "restore defaults with nothing overridden does not claim to have acted", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    view |> element("#settings-restore") |> render_click()

    assert render(view) =~ "already inherited"
  end

  test "hides the tab strip for a single-group page", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    refute has_element?(view, "#settings-tabs")
  end
end
