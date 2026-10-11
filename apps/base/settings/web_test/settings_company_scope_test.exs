defmodule BilimbiWeb.SettingsCompanyScopeTest do
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
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures

  @company_setting "tests.company_limit"

  setup do
    BilimbiWeb.RateLimit.reset({:stored_secret_reveal, 41, 91})
    signed_in_identity!()
    :ok
  end

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

  test "an archived company's settings are shown read-only and a forged save is refused", %{
    conn: conn
  } do
    install_company_setting!()
    grant_capabilities!(["base.settings.company.manage", "admin.company.tenant-wide.manage"])

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Archived company",
      code: "archived_company",
      status: "archived"
    })

    company_scope = Settings.Scope.company(74, 41)
    {:ok, _} = Settings.put(@company_setting, 18, company_scope)
    {:ok, view, _} = open(conn)

    switch_company(view, "73")
    refute has_element?(view, "#settings-company-archived")
    assert has_element?(view, "#settings-save")

    switch_company(view, "74")
    assert has_element?(view, "#settings-company-archived", "archived and read-only")
    assert has_element?(view, "#input-tests-company_limit[value='18']")
    refute has_element?(view, "#settings-save")
    refute has_element?(view, "#settings-restore")
    refute has_element?(view, "#clear-tests-company_limit")

    render_submit(view, "save", %{"settings" => %{@company_setting => "24"}})
    assert has_element?(view, "#flash-error", "archived and read-only")
    assert Settings.get(@company_setting, company_scope) == 18
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

  defp open(conn) do
    grant_capabilities!(["base.settings.global.manage", "admin.authz.decision-log.list"])
    conn |> log_in_as() |> live(~p"/system/settings")
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
end
