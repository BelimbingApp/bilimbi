defmodule BilimbiWeb.ShellPreferencesTest do
  use BilimbiWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.DateTime, as: DateTimePolicy
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @controls Path.expand("../../assets/js/shell_controls.js", __DIR__)
  @theme_css Path.expand("../../assets/css/app.css", __DIR__)

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  test "shell saves theme and timezone only for the authenticated user and survives remount", %{
    conn: conn,
    scope: scope
  } do
    conn = log_in_as(conn)
    {:ok, view, _} = live(conn, ~p"/dashboard")
    render_hook(view, "shell:preference", %{kind: "theme", value: "dark", user_id: 92})
    assert {:ok, "dark"} = User.get_user_preference(scope, 73, 91, "ui.theme")
    assert {:ok, "system"} = User.get_user_preference(scope, 73, 92, "ui.theme")
    assert has_element?(view, "#app-display-dark[aria-pressed='true']")

    render_hook(view, "shell:preference", %{kind: "timezone", value: "utc"})
    assert DateTimePolicy.mode(SettingsScope.user(91, 73, 41)) == :utc
    assert DateTimePolicy.mode(SettingsScope.user(92, 73, 41)) == :company

    {:ok, remounted, _} = live(conn, ~p"/dashboard")
    assert has_element?(remounted, "#app-display-timezone", "UTC")
    assert has_element?(remounted, "#app-display-dark[aria-pressed='true']")
    assert has_element?(remounted, "#app-display-utc[aria-pressed='true']")

    render_hook(remounted, "shell:preference", %{kind: "theme", value: "system"})
    assert {:ok, "system"} = User.get_user_preference(scope, 73, 91, "ui.theme")
  end

  test "invalid values retain the previous preference", %{conn: conn, scope: scope} do
    {:ok, _} = User.put_user_preference(scope, 73, 91, "ui.theme", "light")
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/dashboard")
    render_hook(view, "shell:preference", %{kind: "theme", value: "sepia"})
    render_hook(view, "shell:preference", %{kind: "timezone", value: "Moon/Base"})
    render_hook(view, "shell:preference", %{value: "dark"})
    assert has_element?(view, "#app-display-light[aria-pressed='true']")
    assert {:ok, "light"} = User.get_user_preference(scope, 73, 91, "ui.theme")
    assert DateTimePolicy.mode(SettingsScope.user(91, 73, 41)) == :company
  end

  test "a revoked session cannot keep changing preferences", %{conn: conn, scope: scope} do
    conn = log_in_as(conn)
    session_id = get_session(conn, "current_user")["session_id"]
    {:ok, view, _} = live(conn, ~p"/dashboard")
    :ok = Session.delete_session(session_id)
    render_hook(view, "shell:preference", %{kind: "theme", value: "dark"})
    assert {:ok, "system"} = User.get_user_preference(scope, 73, 91, "ui.theme")
    assert has_element?(view, "#app-display-system[aria-pressed='true']")
  end

  test "a keyboard-only time display save confirms in place without leaving the page", %{
    conn: conn
  } do
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/dashboard?search=ada&sort=name&page=3")

    assert has_element?(view, "#app-display-company[aria-pressed='true']")

    render_hook(view, "shell:preference", %{kind: "timezone", value: "utc"})

    assert DateTimePolicy.mode(SettingsScope.user(91, 73, 41)) == :utc
    assert has_element?(view, "#app-display-utc[aria-pressed='true']")
    assert has_element?(view, "#app-display-company[aria-pressed='false']")
    assert has_element?(view, "#app-display-timezone", "UTC")
    assert has_element?(view, "#app-display-timezone[aria-controls='app-display-timezone-panel']")
  end

  test "an impersonated session is offered no display controls and cannot write them", %{
    conn: conn,
    scope: scope
  } do
    conn =
      conn
      |> log_in_as()
      |> Plug.Test.init_test_session(%{
        "impersonation" => %{"original_user_id" => 92, "original_user_name" => "Grace Hopper"}
      })

    {:ok, view, _} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#app-scope-warning", "Viewing as Ada Lovelace")
    assert has_element?(view, "#app-display-locked", "Company time")
    refute has_element?(view, "#app-display-dark")
    refute has_element?(view, "#app-display-utc")

    render_hook(view, "shell:preference", %{kind: "theme", value: "dark"})
    render_hook(view, "shell:preference", %{kind: "timezone", value: "utc"})

    assert {:ok, "system"} = User.get_user_preference(scope, 73, 91, "ui.theme")
    assert DateTimePolicy.mode(SettingsScope.user(91, 73, 41)) == :company
  end

  test "the account menu exposes real account actions for the signed-in identity", %{conn: conn} do
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/dashboard")
    assert has_element?(view, "#app-user-toggle[aria-controls='app-user-panel']")
    assert has_element?(view, "#app-user-panel", "Ada Lovelace")
    assert has_element?(view, "#app-user-panel", "Company")
    assert has_element?(view, "#app-user-panel", "Tenant")
    assert has_element?(view, "#app-user-password[href='/settings/password']", "Change password")
    assert has_element?(view, "#app-user-logout[data-method='delete']", "Sign out")
    refute has_element?(view, "#app-tenant")
  end

  test "a refused save leaves the feedback region asserting the danger colour and nothing else",
       %{conn: conn} do
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/dashboard")

    rendered =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#app-preference-feedback")
      |> LazyHTML.attribute("class")
      |> hd()

    %{"failed" => failed, "saved" => saved} = feedback_states(rendered)

    # Two colour roles on one element are settled by stylesheet order rather
    # than by the hook, so a second role here means the failure notice may
    # render in ordinary ink. The region inherits `text-ink` from <body>.
    assert colour_roles(failed) == ["text-danger"]
    assert colour_roles(saved) == []
  end

  # Drives the real hook over the region's real rendered classes and reports
  # what each outcome leaves on the element.
  defp feedback_states(class_attribute) do
    source = @controls |> File.read!() |> Base.encode64()

    script = """
    const {default: ShellControls} = await import('data:text/javascript;base64,#{source}')
    const classes = new Set(#{Jason.encode!(class_attribute)}.split(/\\s+/).filter(Boolean))
    const region = {
      hidden: true,
      textContent: '',
      classList: {toggle(name, on) { on ? classes.add(name) : classes.delete(name) }},
    }
    const button = {dataset: {preferenceKind: 'theme', preferenceValue: 'dark'}, focus() {}}
    const root = {
      dataset: {themeChoice: 'light'},
      querySelectorAll: selector => selector === '[data-preference-kind]' ? [button] : [],
      querySelector: () => region,
    }
    globalThis.document = {documentElement: {dataset: {}}, addEventListener() {}, removeEventListener() {}}
    globalThis.window = {addEventListener() {}, removeEventListener() {}}
    const replies = []
    const controls = new ShellControls({el: root, pushEvent(e, p, reply) { replies.push(reply) }})
    const states = {}
    controls.save('theme', 'dark', button)
    replies[0]({ok: false})
    states.failed = [...classes]
    controls.save('theme', 'dark', button)
    replies[1]({ok: true})
    states.saved = [...classes]
    controls.destroy()
    console.log(JSON.stringify(states))
    """

    {out, 0} = System.cmd("node", ["--input-type=module", "-e", script], stderr_to_stdout: true)
    Jason.decode!(out)
  end

  # The `text-*` utilities that carry a semantic colour, read from the roles
  # the theme actually declares.
  defp colour_roles(classes) do
    declared =
      ~r/--color-([a-z0-9-]+)\s*:/
      |> Regex.scan(File.read!(@theme_css))
      |> MapSet.new(fn [_, role] -> "text-" <> role end)

    Enum.filter(classes, &MapSet.member?(declared, &1))
  end
end
