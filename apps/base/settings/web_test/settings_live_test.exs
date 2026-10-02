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

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Definition
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @retention "authz.decision_log_retention_days"
  @input "settings[#{@retention}]"
  @perf_enabled "perf.enabled"
  @perf_enabled_input "settings[#{@perf_enabled}]"
  @stored_secret "tests.operator_api_key"

  setup do
    BilimbiWeb.RateLimit.reset({:stored_secret_reveal, 41, 91})
    UserFixtures.create_user_tables!()
    SettingsFixtures.create_settings_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  defp open(conn) do
    grant_capabilities!(["base.settings.global.manage", "admin.authz.decision-log.list"])
    conn |> log_in_as() |> live(~p"/system/settings")
  end

  test "stored secret starts masked and grant_all confers no reveal action", %{
    conn: conn
  } do
    install_secret!()
    assert {:ok, _} = Settings.put(@stored_secret, "private-example")
    UserFixtures.grant_role!(73, 91, "example_admin", true)

    {:ok, view, html} = open(conn)

    refute html =~ "private-example"
    assert has_element?(view, "#input-tests-operator_api_key[value='••••••••']")
    refute has_element?(view, "#input-tests-operator_api_key-show-stored")
  end

  test "a role that names the reveal capability offers the reveal action", %{conn: conn} do
    install_secret!()
    assert {:ok, _} = Settings.put(@stored_secret, "private-example")
    role_id = UserFixtures.grant_role!(73, 91, "secret_viewer")
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    assert {:ok, 1} =
             Bilimbi.Base.Authz.replace_role_capabilities(scope, role_id, [
               "base.settings.secret.view"
             ])

    {:ok, view, html} = open(conn)

    refute html =~ "private-example"
    assert has_element?(view, "#input-tests-operator_api_key-show-stored")
  end

  test "wrong password refuses and audits a reveal; correct password sends one timed value", %{
    conn: conn
  } do
    install_secret!(1_200)
    assert {:ok, _} = Settings.put(@stored_secret, "private-example")
    grant_capabilities!("base.settings.secret.view")
    {:ok, view, html} = open(conn)

    refute html =~ "private-example"
    assert has_element?(view, "#input-tests-operator_api_key-show-stored")

    view |> element("#input-tests-operator_api_key-show-stored") |> render_click()
    assert has_element?(view, "#secret-reveal-form")
    view |> form("#secret-reveal-form", reveal: %{password: "wrong"}) |> render_submit()
    assert has_element?(view, "#flash-error", "Password was not accepted")
    assert [refusal] = reveal_actions()
    assert refusal.actor_id == 91
    assert refusal.payload["setting_key"] == @stored_secret
    assert refusal.payload["scope_type"] == "global"
    assert refusal.payload["result"] == "refused"
    refute render(view) =~ "private-example"

    view |> form("#secret-reveal-form", reveal: %{password: "password"}) |> render_submit()

    assert_push_event(view, "secret:reveal", %{
      id: "input-tests-operator_api_key",
      value: "private-example",
      duration_ms: 1_200
    })

    refute render(view) =~ "private-example"
    assert Enum.map(reveal_actions(), & &1.payload["result"]) == ["refused", "succeeded"]
  end

  test "a value deleted while confirming is reported as unavailable, not as a wrong password",
       %{conn: conn} do
    install_secret!()
    assert {:ok, _} = Settings.put(@stored_secret, "private-example")
    grant_capabilities!("base.settings.secret.view")
    {:ok, view, _html} = open(conn)
    view |> element("#input-tests-operator_api_key-show-stored") |> render_click()

    Settings.delete(@stored_secret)
    view |> form("#secret-reveal-form", reveal: %{password: "password"}) |> render_submit()

    assert has_element?(view, "#flash-error", "This stored value cannot be shown")
    refute has_element?(view, "#secret-reveal-form")
    assert [%{payload: %{"result" => "refused"}}] = reveal_actions()
  end

  test "failed passwords are throttled and each refusal is audited", %{conn: conn} do
    install_secret!()
    assert {:ok, _} = Settings.put(@stored_secret, "private-example")
    grant_capabilities!("base.settings.secret.view")
    {:ok, view, _html} = open(conn)
    view |> element("#input-tests-operator_api_key-show-stored") |> render_click()

    for _ <- 1..5 do
      view |> form("#secret-reveal-form", reveal: %{password: "wrong"}) |> render_submit()
    end

    view |> form("#secret-reveal-form", reveal: %{password: "password"}) |> render_submit()
    assert has_element?(view, "#flash-error", "Too many attempts")
    assert length(reveal_actions()) == 6
    refute render(view) =~ "private-example"
  end

  test "an unavailable audit store refuses the reveal and never sends the value", %{conn: conn} do
    install_secret!()
    assert {:ok, _} = Settings.put(@stored_secret, "private-example")
    grant_capabilities!("base.settings.secret.view")
    {:ok, view, _html} = open(conn)
    view |> element("#input-tests-operator_api_key-show-stored") |> render_click()

    # Remove only this sandbox connection's temporary fixture, and search only
    # the temporary schema so the insert cannot fall through to a persistent
    # `public.base_audit_actions`. Both are rolled back with the sandbox.
    Ecto.Adapters.SQL.query!(Bilimbi.Base.Repo, "SET LOCAL search_path TO pg_temp", [])
    Ecto.Adapters.SQL.query!(Bilimbi.Base.Repo, "DROP TABLE pg_temp.base_audit_actions", [])

    view |> form("#secret-reveal-form", reveal: %{password: "password"}) |> render_submit()

    assert has_element?(
             view,
             "#flash-error",
             "The reveal could not be recorded, so the value was not shown"
           )

    refute_push_event(view, "secret:reveal", %{})
    refute render(view) =~ "private-example"
    assert has_element?(view, "#secret-reveal-form")
  end

  defp reveal_actions do
    {:ok, scope} = Bilimbi.Base.Tenancy.scope(41)

    {:ok, actions} = Audit.list_actions(scope)
    Enum.filter(actions, &(&1.event == "settings.secret.reveal")) |> Enum.sort_by(& &1.id)
  end

  defp install_secret!(reveal_duration_ms \\ 10_000, scopes \\ [:global]) do
    installed = ContributionRegistry.snapshot!()
    on_exit(fn -> ContributionRegistry.put_snapshot_for_test!(installed) end)

    definition =
      Definition.new!(@stored_secret, "tests/secret", %{
        type: :string,
        scopes: scopes,
        default: nil,
        nullable: true,
        encrypted: true,
        reveal_duration_ms: reveal_duration_ms,
        label: "API key",
        help: "Credential for the upstream service.",
        editable: "operator",
        capability: "base.settings.global.manage"
      })

    ContributionRegistry.put_snapshot_for_test!(
      update_in(
        installed,
        [:consumers, :settings, :definitions],
        &Map.put(&1, @stored_secret, definition)
      )
    )
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

  test "company secrets stay masked and revoked access refuses and audits a pending reveal", %{
    conn: conn
  } do
    install_secret!(1_200, [:global, :company])
    target = Settings.Scope.company(73, 41)
    assert {:ok, _} = Settings.put(@stored_secret, "company-private-example", target)
    grant_capabilities!(["base.settings.company.manage", "base.settings.secret.view"])
    {:ok, view, _} = open(conn)
    switch_company(view, "73")
    assert has_element?(view, "#input-tests-operator_api_key[value='••••••••']")
    refute render(view) =~ "company-private-example"
    view |> element("#input-tests-operator_api_key-show-stored") |> render_click()
    {:ok, tenant_scope} = Bilimbi.Base.Tenancy.scope(41)

    assert {:ok, :stored} =
             Bilimbi.Base.Authz.put_principal_capability(
               tenant_scope,
               73,
               :user,
               91,
               "base.settings.company.manage",
               false
             )

    view |> form("#secret-reveal-form", reveal: %{password: "password"}) |> render_submit()
    assert has_element?(view, "#flash-error", "cannot be shown")
    refute_push_event(view, "secret:reveal", %{})

    assert [%{payload: %{"result" => "refused", "scope_type" => "company", "scope_id" => 73}}] =
             reveal_actions()
  end

  @company_setting "tests.company_limit"

  test "company scope displays inheritance, saves and audits an override, then clears it", %{
    conn: conn
  } do
    install_company_setting!()
    grant_capabilities!("base.settings.company.manage")
    assert {:ok, 12} = Settings.put(@company_setting, 12)
    {:ok, view, _} = open(conn)
    switch_company(view, "73")
    company_scope = Settings.Scope.company(73, 41)

    assert has_element?(view, "#input-tests-company_limit[value='12']")
    assert has_element?(view, "#setting-tests-company_limit", "Inherited from global")
    refute has_element?(view, "#setting-webhooks-max_bytes")
    view |> form("#settings-form", %{"settings[tests.company_limit]" => "24"}) |> render_submit()
    assert Settings.get(@company_setting, company_scope) == 24
    assert Settings.get(@company_setting) == 12
    assert has_element?(view, "#setting-tests-company_limit", "Company override")

    {:ok, tenant_scope} = Bilimbi.Base.Tenancy.scope(41)
    {:ok, mutations} = Audit.list_mutations(tenant_scope)

    assert Enum.any?(mutations, fn mutation ->
             mutation.actor_id == 91 and mutation.new_values["key"] == @company_setting and
               mutation.new_values["scope_type"] == "company" and
               mutation.new_values["scope_id"] == 73
           end)

    view |> element("#clear-tests-company_limit") |> render_click()
    view |> element("#restore-defaults-confirm-confirm") |> render_click()
    refute Settings.overridden?(@company_setting, company_scope)
    assert has_element?(view, "#input-tests-company_limit[value='12']")
    assert has_element?(view, "#flash-success", "1 override cleared")
    {:ok, mutations} = Audit.list_mutations(tenant_scope)

    assert Enum.any?(
             mutations,
             &(&1.actor_id == 91 and &1.old_values["key"] == @company_setting and
                 &1.event == "deleted")
           )
  end

  test "switching scope discards confirmations and keeps global and company writes separate", %{
    conn: conn
  } do
    install_company_setting!()
    grant_capabilities!(["base.settings.company.manage", "admin.company.tenant-wide.manage"])

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Second company",
      code: "second_company"
    })

    {:ok, _} = Settings.put(@company_setting, 18, Settings.Scope.company(73, 41))
    {:ok, view, _} = open(conn)
    switch_company(view, "73")
    view |> element("#clear-tests-company_limit") |> render_click()
    switch_company(view, "74")
    refute has_element?(view, "#restore-defaults-confirm")
    view |> render_click("restore_defaults", %{})
    assert Settings.get(@company_setting, Settings.Scope.company(73, 41)) == 18
    assert has_element?(view, "#input-tests-company_limit[value='6']")
    assert has_element?(view, "#setting-tests-company_limit", "Inherited from the default")
    switch_company(view, "global")
    assert has_element?(view, "#setting-webhooks-max_bytes")
    assert has_element?(view, "#input-tests-company_limit[value='6']")
  end

  test "discovers company-only settings in another declared group", %{conn: conn} do
    installed = ContributionRegistry.snapshot!()
    on_exit(fn -> ContributionRegistry.put_snapshot_for_test!(installed) end)

    definition =
      Definition.new!("tests.company_only", "tests/company", %{
        type: :boolean,
        scopes: [:company],
        default: true,
        label: "Company feature",
        help: "Enable the feature.",
        editable: "team",
        capability: "base.settings.company.manage"
      })

    ContributionRegistry.put_snapshot_for_test!(
      update_in(
        installed,
        [:consumers, :settings, :definitions],
        &Map.put(&1, "tests.company_only", definition)
      )
    )

    grant_capabilities!("base.settings.company.manage")
    {:ok, view, _} = open(conn)
    refute has_element?(view, "#setting-tests-company_only")
    switch_company(view, "73")

    if has_element?(view, "#settings-tab-team") do
      view |> element("#settings-tab-team") |> render_click()
    end

    assert has_element?(view, "#input-tests-company_only[checked]")

    view
    |> form("#settings-form", %{"settings[tests.company_only]" => "false"})
    |> render_submit()

    assert Settings.get("tests.company_only", Settings.Scope.company(73, 41)) == false
    view |> element("#clear-tests-company_only") |> render_click()
    view |> element("#restore-defaults-confirm-confirm") |> render_click()
    assert has_element?(view, "#input-tests-company_only[checked]")
  end

  test "company scope refuses invalid values and forged global-only writes", %{conn: conn} do
    install_company_setting!()
    grant_capabilities!("base.settings.company.manage")
    {:ok, view, _} = open(conn)
    switch_company(view, "73")
    view |> form("#settings-form", %{"settings[tests.company_limit]" => "bad"}) |> render_submit()
    assert has_element?(view, "#flash-error", "must be a whole number")
    refute Settings.overridden?(@company_setting, Settings.Scope.company(73, 41))
    view |> render_submit("save", %{"settings" => %{"webhooks.max_bytes" => "42"}})
    refute Settings.overridden?("webhooks.max_bytes")
  end

  test "company selection is capability gated and limited to authorized live targets", %{
    conn: conn
  } do
    install_company_setting!()

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Other company",
      code: "other_company"
    })

    CompanyFixtures.insert_tenant!(%{id: 42, is_platform_operator: false})

    CompanyFixtures.insert_company!(%{
      id: 75,
      tenant_id: 42,
      name: "Outside company",
      code: "outside_company"
    })

    CompanyFixtures.insert_company!(%{
      id: 76,
      tenant_id: 41,
      name: "Removed company",
      code: "removed_company",
      deleted_at: ~N[2026-01-01 00:00:00]
    })

    {:ok, view, _} = open(conn)
    refute has_element?(view, "#settings-company")
    view |> render_change("switch_scope", %{"scope" => %{"company_id" => "73"}})
    assert has_element?(view, "#flash-error", "permission")
    assert has_element?(view, "#setting-webhooks-max_bytes")

    grant_capabilities!("base.settings.company.manage")
    {:ok, view, _} = open(conn)
    assert has_element?(view, "#settings-company option[value='73']")
    refute has_element?(view, "#settings-company option[value='74']")
    refute has_element?(view, "#settings-company option[value='75']")
    refute has_element?(view, "#settings-company option[value='76']")

    for id <- ["75", "76"] do
      view |> render_change("switch_scope", %{"scope" => %{"company_id" => id}})
      assert has_element?(view, "#flash-error", "permission")
    end

    view |> render_change("switch_scope", %{"scope" => %{"company_id" => "74"}})
    assert has_element?(view, "#flash-error", "permission")
    view |> render_change("switch_scope", %{"scope" => %{"company_id" => "999"}})
    assert has_element?(view, "#flash-error", "permission")
  end

  test "revoked company capability refuses saves and clearing after selection", %{conn: conn} do
    install_company_setting!()
    grant_capabilities!(["base.settings.company.manage", "admin.company.tenant-wide.manage"])

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Other company",
      code: "other_company"
    })

    target = Settings.Scope.company(74, 41)
    {:ok, _} = Settings.put(@company_setting, 18, target)
    {:ok, view, _} = open(conn)
    switch_company(view, "74")
    view |> element("#clear-tests-company_limit") |> render_click()
    {:ok, tenant_scope} = Bilimbi.Base.Tenancy.scope(41)

    assert {:ok, :stored} =
             Bilimbi.Base.Authz.put_principal_capability(
               tenant_scope,
               73,
               :user,
               91,
               "base.settings.company.manage",
               false
             )

    view |> element("#restore-defaults-confirm-confirm") |> render_click()
    assert has_element?(view, "#flash-error", "permission")
    assert Settings.overridden?(@company_setting, target)
    view |> render_submit("save", %{"settings" => %{@company_setting => "25"}})
    assert has_element?(view, "#flash-error", "permission")
    assert Settings.get(@company_setting, target) == 18
  end

  test "company scope refuses an invalid timezone with the owner's rule and saves a valid one",
       %{conn: conn} do
    grant_capabilities!(["base.settings.company.manage", "admin.company.update"])
    company_scope = Settings.Scope.company(73, 41)
    {:ok, view, _} = open(conn)
    switch_company(view, "73")

    if has_element?(view, "#settings-tab-company\\.profile") do
      view |> element("#settings-tab-company\\.profile") |> render_click()
    end

    view
    |> form("#settings-form", %{"settings[localization.timezone]" => "Asia/Kuala_Lumpr"})
    |> render_submit()

    assert has_element?(view, "#flash-error", "must be a valid IANA timezone")
    refute Settings.overridden?("localization.timezone", company_scope)

    view
    |> form("#settings-form", %{"settings[localization.timezone]" => "Asia/Kuala_Lumpur"})
    |> render_submit()

    assert Settings.get("localization.timezone", company_scope) == "Asia/Kuala_Lumpur"
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

  defp switch_company(view, id) do
    view |> form("#settings-scope-form", %{"scope[company_id]" => id}) |> render_change()
  end

  defp install_company_setting! do
    installed = ContributionRegistry.snapshot!()
    on_exit(fn -> ContributionRegistry.put_snapshot_for_test!(installed) end)

    definition =
      Definition.new!(@company_setting, "tests/company", %{
        type: :integer,
        scopes: [:global, :company],
        default: 6,
        label: "Company limit",
        help: "Limit for the company.",
        editable: "operator",
        capability: "base.settings.global.manage"
      })

    ContributionRegistry.put_snapshot_for_test!(
      update_in(
        installed,
        [:consumers, :settings, :definitions],
        &Map.put(&1, @company_setting, definition)
      )
    )
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
        Map.reject(definitions, fn {_key, definition} ->
          definition.editable == "operator" and definition.capability not in capabilities
        end)
      end)
    )
  end

  # The installed snapshot minus every setting editable in the operator group,
  # restored on exit. Other definitions stay so the shell's own reads resolve.
  defp without_operator_settings! do
    installed = ContributionRegistry.snapshot!()
    on_exit(fn -> ContributionRegistry.put_snapshot_for_test!(installed) end)

    ContributionRegistry.put_snapshot_for_test!(
      update_in(installed, [:consumers, :settings, :definitions], fn definitions ->
        Map.reject(definitions, fn {_key, definition} -> definition.editable == "operator" end)
      end)
    )
  end
end
