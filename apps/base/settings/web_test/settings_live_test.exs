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

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Definition
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @retention "authz.decision_log_retention_days"
  @input "settings[#{@retention}]"
  @perf_enabled "perf.enabled"
  @perf_enabled_input "settings[#{@perf_enabled}]"

  setup do
    BilimbiWeb.RateLimit.reset({:stored_secret_reveal, 41, 91})
    signed_in_identity!()
    :ok
  end

  test "a non-operator tenant cannot change platform-global settings", %{conn: conn} do
    CompanyFixtures.insert_tenant!(%{id: 42, is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 74, tenant_id: 42, code: "other_company"})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 74,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    grant_capabilities!("base.settings.global.manage",
      tenant_id: 42,
      company_id: 74,
      user_id: 92
    )

    assert {:ok, _entry} = Settings.put("webhooks.rate_limit", 120)
    conn = log_in_as(conn, session_user(%{"user_id" => 92, "company_id" => 74}))

    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/system/settings")
    assert Settings.get("webhooks.rate_limit") == 120
  end

  test "global save and restore refuse a scope that lost base.settings.global.manage", %{
    conn: conn
  } do
    {:ok, scope} = Tenancy.scope(41)
    user = Authentication.sign_in(scope, 91, 73)
    fields = Settings.Form.fields(["operator"], nil)

    assert {:error, :forbidden} = Settings.Form.save(%{@retention => "30"}, fields, nil, user)
    assert Settings.get(@retention) == 90

    grant_capabilities!("base.settings.global.manage")

    assert {:ok, %{written: [@retention]}} =
             Settings.Form.save(%{@retention => "30"}, fields, nil, user)

    assert Settings.get(@retention) == 30

    revoke_global_manage!(scope)

    assert {:error, :forbidden} = Settings.Form.restore_defaults(fields, nil, user)
    assert Settings.get(@retention) == 30

    grant_capabilities!("base.settings.global.manage")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/settings")
    revoke_global_manage!(scope)

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             render_submit(view, "save", %{"settings" => %{@retention => "12"}})

    assert Settings.get(@retention) == 30
  end

  test "definition capabilities hide and reject unauthorized settings", %{conn: conn} do
    grant_capabilities!("base.settings.global.manage")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/settings")

    refute has_element?(view, "#setting-perf-enabled")
    view |> render_submit("save", %{"settings" => %{"perf.enabled" => "false"}})
    refute Settings.overridden?("perf.enabled")

    grant_capabilities!("admin.system.perf.manage")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/settings")
    assert has_element?(view, "#setting-perf-enabled")
  end

  test "a group nothing contributes to says so, not that it is out of reach", %{conn: conn} do
    without_operator_settings!()
    grant_capabilities!("base.settings.global.manage")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/settings")

    assert has_element?(
             view,
             "#settings-group-operator-empty",
             "No installed module contributes settings to this group."
           )

    refute has_element?(view, "#settings-group-operator-withheld")
  end

  test "a group whose settings the account may not see names the capabilities", %{conn: conn} do
    # Keep the fixture's fields behind permissions this account does not hold.
    # Some installed fields legitimately use the page capability itself.
    only_operator_settings_needing!(operator_capabilities() -- ["base.settings.global.manage"])
    grant_capabilities!("base.settings.global.manage")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/settings")

    refute has_element?(view, "#settings-group-operator-empty")
    refute render(view) =~ "No installed module contributes"

    assert has_element?(
             view,
             "#settings-group-operator-withheld",
             "You do not have permission to see the settings in this group"
           )

    assert has_element?(
             view,
             "#settings-group-operator-withheld",
             "Ask an operator to review your role."
           )

    # Named in the key form the Roles and Capabilities pages use, one per
    # capability the withheld settings require, so the reader knows what to
    # ask for.
    required = operator_capabilities()
    assert "admin.system.perf.manage" in required

    for capability <- required do
      assert has_element?(view, "#settings-group-operator-withheld", capability)
    end

    # Each setting needs its own capability, so no single grant is offered as
    # the key to the whole group.
    {rest, [last]} = required |> Enum.sort() |> Enum.split(-1)

    assert has_element?(
             view,
             "#settings-group-operator-withheld",
             "You do not have permission to see the settings in this group; each setting " <>
               "needs its own permission, and this group uses #{Enum.join(rest, ", ")} and #{last}."
           )

    refute has_element?(view, "#settings-group-operator-withheld", "one of")
  end

  test "a group withheld by one capability names it alone", %{conn: conn} do
    only_operator_settings_needing!("admin.system.perf.manage")
    grant_capabilities!("base.settings.global.manage")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/settings")

    assert has_element?(
             view,
             "#settings-group-operator-withheld",
             "You do not have permission to see the settings in this group, each of which " <>
               "needs admin.system.perf.manage."
           )

    refute has_element?(view, "#settings-group-operator-withheld", "its own permission")
    refute has_element?(view, "#settings-group-operator-withheld", "one of")
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

  test "webhook protection settings can be edited and invalid limits are refused", %{conn: conn} do
    grant_capabilities!("base.settings.global.manage")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/settings")

    values = %{
      "webhooks.max_bytes" => 4096,
      "webhooks.rate_limit" => 20,
      "webhooks.window_ms" => 30_000,
      "webhooks.read_timeout_ms" => 5000
    }

    for {key, _value} <- values do
      assert has_element?(view, "#input-#{String.replace(key, ".", "-")}[type='number']")
    end

    params = Map.new(values, fn {key, value} -> {"settings[#{key}]", to_string(value)} end)
    view |> form("#settings-form", params) |> render_submit()

    for {key, value} <- values do
      assert Settings.get(key) == value
      assert has_element?(view, "#setting-#{String.replace(key, ".", "-")}", "Set here")
    end

    view |> form("#settings-form", %{"settings[webhooks.max_bytes]" => "0"}) |> render_submit()
    assert has_element?(view, "#flash-error")
    assert Settings.get("webhooks.max_bytes") == 4096
  end

  test "saving marks the field as set here", %{conn: conn} do
    only_operator_settings_needing!("admin.authz.decision-log.list")
    {:ok, view, _html} = open(conn)

    view |> form("#settings-form", %{@input => "45"}) |> render_submit()

    assert Settings.get(@retention) == 45
    assert has_element?(view, "#setting-authz-decision_log_retention_days", "Set here")
    assert has_element?(view, "#flash-success", "1 setting updated")
    refute has_element?(view, "#flash-info")
  end

  test "clearing a field says so, and the value returns to its default", %{conn: conn} do
    assert {:ok, 45} = Settings.put(@retention, 45)
    {:ok, view, _html} = open(conn)

    view |> form("#settings-form", %{@input => ""}) |> render_submit()

    # The distinction that matters: the value is back to 90 and the page says
    # an override was cleared, rather than reporting a save that looks empty.
    assert Settings.get(@retention) == 90
    refute Settings.overridden?(@retention)
    assert has_element?(view, "#flash-success", "1 override cleared")
    refute has_element?(view, "#flash-info")
  end

  test "reports a rejected value against the field, and writes nothing", %{conn: conn} do
    assert {:ok, 45} = Settings.put(@retention, 45)
    {:ok, view, _html} = open(conn)

    view |> form("#settings-form", %{@input => "not-a-number"}) |> render_submit()

    assert render(view) =~ "Authorization log retention"
    assert render(view) =~ "must be a whole number"
    assert Settings.get(@retention) == 45
  end

  test "renders boolean settings as checkboxes and saves explicit false values", %{conn: conn} do
    grant_capabilities!(["base.settings.global.manage", "admin.system.perf.manage"])
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/system/settings")

    assert has_element?(
             view,
             "#input-perf-enabled[type='checkbox'][name='settings[perf.enabled]'][value='true'][checked]"
           )

    assert has_element?(
             view,
             "#setting-perf-enabled input[type='hidden'][name='settings[perf.enabled]'][value='false']"
           )

    view |> form("#settings-form", %{@perf_enabled_input => "false"}) |> render_submit()

    assert Settings.get(@perf_enabled) == false
    assert Settings.overridden?(@perf_enabled)
    refute has_element?(view, "#input-perf-enabled[checked]")

    view |> form("#settings-form", %{@perf_enabled_input => "true"}) |> render_submit()

    assert Settings.get(@perf_enabled) == true
    assert has_element?(view, "#input-perf-enabled[checked]")
  end

  test "submitting the default value still creates an override", %{conn: conn} do
    only_operator_settings_needing!("admin.authz.decision-log.list")
    {:ok, view, _html} = open(conn)

    view |> form("#settings-form", %{@input => "90"}) |> render_submit()

    # 90 is also the default, but typing it is a decision to pin it here rather
    # than keep inheriting. Belimbing writes in this case too; only an empty
    # field means "stop overriding". Asserted so nobody "optimises" the write
    # away and silently turns a pin into an inherit.
    assert Settings.overridden?(@retention)
    assert render(view) =~ "1 setting updated"
  end

  test "a submission that touches nothing reports no change", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    # No settings key at all: the form submitted nothing this page owns.
    view |> render_submit("save", %{})

    # Nothing was written, so the page informs rather than confirms.
    assert has_element?(view, "#flash-info", "No changes to save.")
    refute has_element?(view, "#flash-success")
  end

  test "restore defaults confirms the overrides it removes, then clears them", %{conn: conn} do
    assert {:ok, 45} = Settings.put(@retention, 45)
    {:ok, view, _html} = open(conn)

    # Restoring confirms through the shared dialog, which counts the overrides
    # it will remove and says what cannot be undone; no native confirm remains.
    refute has_element?(view, "#settings-restore[data-confirm]")
    view |> element("#settings-restore") |> render_click()

    assert_modal_dialog(
      view,
      "restore-defaults-confirm",
      "1 override on this page will be removed."
    )

    assert has_element?(view, "dialog#restore-defaults-confirm[role='alertdialog']")

    assert has_element?(
             view,
             "#restore-defaults-confirm-description",
             "Each of those settings returns to the value it inherits. This cannot be undone."
           )

    # Cancelling keeps the override.
    view |> element("#restore-defaults-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(view, "#restore-defaults-confirm")
    assert Settings.overridden?(@retention)

    # Confirming clears it and reports the completed write as a success.
    view |> element("#settings-restore") |> render_click()

    assert has_element?(
             view,
             "#restore-defaults-confirm-confirm[phx-disable-with='Restoring…']",
             "Restore"
           )

    view |> element("#restore-defaults-confirm-confirm") |> render_click()
    refute has_element?(view, "#restore-defaults-confirm")

    refute Settings.overridden?(@retention)
    assert has_element?(view, "#flash-success", "1 override cleared")
  end

  test "restore defaults with nothing overridden does not ask or claim to have acted", %{
    conn: conn
  } do
    {:ok, view, _html} = open(conn)

    view |> element("#settings-restore") |> render_click()

    refute has_element?(view, "#restore-defaults-confirm")
    assert render(view) =~ "already inherited"
  end

  test "hides the tab strip for a single-group page", %{conn: conn} do
    {:ok, view, _html} = open(conn)

    refute has_element?(view, "#settings-tabs")
  end

  test "global scope runs a definition's validator before saving", %{conn: conn} do
    installed = ContributionRegistry.snapshot!()
    on_exit(fn -> ContributionRegistry.put_snapshot_for_test!(installed) end)

    definition =
      Definition.new!("tests.operator_timezone", "tests/timezone", %{
        type: :string,
        scopes: [:global],
        default: "UTC",
        label: "Operator timezone",
        help: "Timezone for operator reports.",
        editable: "operator",
        capability: "base.settings.global.manage",
        validator: {Bilimbi.Base.DateTime, :valid_timezone?, "must be a valid IANA timezone"}
      })

    ContributionRegistry.put_snapshot_for_test!(
      update_in(
        installed,
        [:consumers, :settings, :definitions],
        &Map.put(&1, "tests.operator_timezone", definition)
      )
    )

    {:ok, view, _} = open(conn)

    view
    |> form("#settings-form", %{"settings[tests.operator_timezone]" => "Mars/Olympus"})
    |> render_submit()

    assert has_element?(view, "#flash-error", "must be a valid IANA timezone")
    refute Settings.overridden?("tests.operator_timezone")

    view
    |> form("#settings-form", %{"settings[tests.operator_timezone]" => "Europe/Paris"})
    |> render_submit()

    assert Settings.get("tests.operator_timezone") == "Europe/Paris"
  end

  test "the Settings API refuses an invalid timezone with the validator message" do
    company_scope = Settings.Scope.company(73, 41)

    assert {:error, changeset} =
             Settings.put("localization.timezone", "Asia/Kuala_Lumpr", company_scope)

    assert {"must be a valid IANA timezone", _} = changeset.errors[:value]
    refute Settings.overridden?("localization.timezone", company_scope)

    assert {:ok, "Asia/Kuala_Lumpur"} =
             Settings.put("localization.timezone", "Asia/Kuala_Lumpur", company_scope)
  end

  defp open(conn) do
    grant_capabilities!(["base.settings.global.manage", "admin.authz.decision-log.list"])
    conn |> log_in_as() |> live(~p"/system/settings")
  end

  defp revoke_global_manage!(scope) do
    grant =
      scope
      |> Authz.list_principal_capabilities(page_size: 100)
      |> Map.fetch!(:entries)
      |> Enum.find(&(&1.capability == "base.settings.global.manage"))

    assert {:ok, :removed} = Authz.remove_principal_capability(scope, grant.id)
  end

  defp operator_capabilities do
    Settings.definitions()
    |> Map.values()
    |> Enum.filter(&(&1.editable == "operator"))
    |> Enum.map(& &1.capability)
    |> Enum.uniq()
  end

  # The installed snapshot keeping only the operator settings gated by
  # the named capabilities, restored on exit.
  defp only_operator_settings_needing!(capabilities) do
    capabilities = List.wrap(capabilities)
    installed = ContributionRegistry.snapshot!()
    on_exit(fn -> ContributionRegistry.put_snapshot_for_test!(installed) end)

    ContributionRegistry.put_snapshot_for_test!(
      update_in(installed, [:consumers, :settings, :definitions], fn definitions ->
        definitions
        |> hide_session_settings!()
        |> Map.reject(fn {_key, definition} ->
          definition.editable == "operator" and definition.capability not in capabilities
        end)
      end)
    )
  end

  defp hide_session_settings!(definitions) do
    # Authentication still needs the lifetime and the touch interval when the
    # operator group is narrowed.
    Enum.reduce(
      ["session.lifetime_minutes", "session.last_activity_touch_minutes"],
      definitions,
      fn key, acc ->
        Map.update!(acc, key, &%{&1 | editable: nil})
      end
    )
  end

  # The installed snapshot minus every setting editable in the operator group,
  # restored on exit. Other definitions stay so the shell's own reads resolve.
  defp without_operator_settings! do
    installed = ContributionRegistry.snapshot!()
    on_exit(fn -> ContributionRegistry.put_snapshot_for_test!(installed) end)

    ContributionRegistry.put_snapshot_for_test!(
      update_in(installed, [:consumers, :settings, :definitions], fn definitions ->
        definitions
        |> hide_session_settings!()
        |> Map.reject(fn {_key, definition} -> definition.editable == "operator" end)
      end)
    )
  end
end
