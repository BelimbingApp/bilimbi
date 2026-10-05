defmodule BilimbiWeb.SettingsSecretRevealTest do
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
  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Definition

  @stored_secret "tests.operator_api_key"

  setup do
    BilimbiWeb.RateLimit.reset({:stored_secret_reveal, 41, 91})
    signed_in_identity!()
    :ok
  end

  test "stored secret starts masked and grant_all confers no reveal action", %{
    conn: conn
  } do
    install_secret!()
    assert {:ok, _} = Settings.put(@stored_secret, "private-example")
    AuthzFixtures.grant_role!(73, 91, "example_admin", true)

    {:ok, view, html} = open(conn)

    refute html =~ "private-example"
    assert has_element?(view, "#input-tests-operator_api_key[value='••••••••']")
    refute has_element?(view, "#input-tests-operator_api_key-show-stored")
  end

  test "a role that names the reveal capability offers the reveal action", %{conn: conn} do
    install_secret!()
    assert {:ok, _} = Settings.put(@stored_secret, "private-example")
    role_id = AuthzFixtures.grant_role!(73, 91, "secret_viewer")
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

  defp open(conn) do
    grant_capabilities!(["base.settings.global.manage", "admin.authz.decision-log.list"])
    conn |> log_in_as() |> live(~p"/system/settings")
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

  defp switch_company(view, id) do
    view |> form("#settings-scope-form", %{"scope[company_id]" => id}) |> render_change()
  end
end
