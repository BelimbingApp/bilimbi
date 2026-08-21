defmodule BilimbiWeb.UserAuthLocaleTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Locale
  alias Bilimbi.Base.Settings.Scope, as: SettingsScope
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    UserFixtures.insert_user!(%{
      id: 91,
      company_id: 73,
      name: "Ada Lovelace",
      email: "ada@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    :ok
  end

  test "applies the account language to HTTP requests and resets anonymous requests globally", %{
    conn: conn
  } do
    assert {:ok, "fr-FR"} = Locale.put(nil, "fr-FR")
    assert {:ok, "de-CH"} = Locale.put(SettingsScope.user(91, 73, 41), "de-CH")

    conn = conn |> log_in_as() |> get(~p"/dashboard")
    assert html_response(conn, 200)
    assert Gettext.get_locale(BilimbiWeb.Gettext) == "de"
    assert Gettext.get_locale(Bilimbi.Base.UI.Gettext) == "de"

    anonymous_conn = build_conn() |> get(~p"/")
    assert html_response(anonymous_conn, 200)
    assert Gettext.get_locale(BilimbiWeb.Gettext) == "fr"
    assert Gettext.get_locale(Bilimbi.Base.UI.Gettext) == "fr"
  end

  test "keeps concurrent LiveView languages isolated by account" do
    assert {:ok, "de-CH"} = Locale.put(SettingsScope.user(91, 73, 41), "de-CH")
    assert {:ok, "zh-TW"} = Locale.put(SettingsScope.user(92, 73, 41), "zh-TW")

    {:ok, first_view, _html} =
      build_conn()
      |> log_in_as(session_user(%{"user_id" => 91}))
      |> live(~p"/dashboard")

    {:ok, second_view, _html} =
      build_conn()
      |> log_in_as(session_user(%{"user_id" => 92}))
      |> live(~p"/dashboard")

    assert process_gettext_locale(first_view.pid, BilimbiWeb.Gettext) == "de"
    assert process_gettext_locale(first_view.pid, Bilimbi.Base.UI.Gettext) == "de"
    assert process_gettext_locale(second_view.pid, BilimbiWeb.Gettext) == "zh"
    assert process_gettext_locale(second_view.pid, Bilimbi.Base.UI.Gettext) == "zh"
  end

  defp process_gettext_locale(pid, backend) do
    {:dictionary, dictionary} = Process.info(pid, :dictionary)
    {^backend, locale} = List.keyfind(dictionary, backend, 0)
    locale
  end
end
