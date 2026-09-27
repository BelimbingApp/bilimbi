defmodule BilimbiWeb.FramedRenderTest do
  @moduledoc """
  A page requested by a frame renders without the shell's chrome, through
  the session MFA on every discovered `live_session` and the `on_mount`
  hook that reads it back. The flag never touches the cookie session.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias BilimbiWeb.FramedRender

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  defp framed(conn), do: put_req_header(conn, "sec-fetch-dest", "iframe")

  test "a framed request renders the page without top bar, sidebar or status bar", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> framed() |> live(~p"/dashboard")

    assert has_element?(view, "#app-shell[data-framed='true'][data-display-mode]")
    assert has_element?(view, "#app-content")
    refute has_element?(view, "#app-topbar")
    refute has_element?(view, "#app-sidebar")
    refute has_element?(view, "#app-statusbar")
    refute has_element?(view, "#app-mode")
  end

  test "an ordinary request keeps the whole shell", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/dashboard")

    refute has_element?(view, "#app-shell[data-framed]")
    assert has_element?(view, "#app-topbar")
    assert has_element?(view, "#app-sidebar")
    assert has_element?(view, "#app-statusbar #app-mode[hidden]")
  end

  test "the flag travels in the LiveView session, not the cookie", %{conn: conn} do
    conn = conn |> log_in_as() |> framed() |> get(~p"/dashboard")

    assert FramedRender.session(conn) == %{"bilimbi_framed" => true}
    refute Map.has_key?(get_session(conn), "bilimbi_framed")
    assert FramedRender.session(build_conn()) == %{"bilimbi_framed" => false}
  end

  test "the mount hook marks a scope only when the session carries the flag" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_scope: %{user: %{}}}}

    assert {:cont, marked} =
             FramedRender.on_mount(:framed, %{}, %{"bilimbi_framed" => true}, socket)

    assert marked.assigns.current_scope.framed == true

    assert {:cont, ^socket} =
             FramedRender.on_mount(:framed, %{}, %{"bilimbi_framed" => false}, socket)

    assert {:cont, ^socket} = FramedRender.on_mount(:framed, %{}, %{}, socket)

    anonymous = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_scope: nil}}

    assert {:cont, ^anonymous} =
             FramedRender.on_mount(:framed, %{}, %{"bilimbi_framed" => true}, anonymous)
  end
end
