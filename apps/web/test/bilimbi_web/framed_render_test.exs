defmodule BilimbiWeb.FramedRenderTest do
  @moduledoc """
  A page requested by a frame renders without the shell's chrome, through
  the session MFA on every discovered `live_session` and the `on_mount`
  hook that reads it back. The flag never touches the cookie session.
  """

  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
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

  defp pin_reads(count \\ 0) do
    receive do
      :pin_read -> pin_reads(count + 1)
    after
      0 -> count
    end
  end

  test "a framed request renders the page without top bar, sidebar or status bar", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_as() |> framed() |> live(~p"/dashboard")

    assert has_element?(view, "#app-shell[data-framed='true'][data-display-mode]")
    assert has_element?(view, "#app-content")

    send(view.pid, :refresh_widgets)
    assert has_element?(view, "#app-shell[data-framed='true'][data-display-mode]")
    refute has_element?(view, "#app-topbar")
    refute has_element?(view, "#app-sidebar")
    refute has_element?(view, "#app-statusbar")
    refute has_element?(view, "#app-mode")
  end

  test "a framed page does not query shell pins", %{conn: conn} do
    UserFixtures.create_user_pins_table!()
    {:ok, scope} = Tenancy.scope(41)
    scope = Tenancy.Authentication.sign_in(scope, 91, 73)

    {:ok, :pinned, _} =
      User.toggle_user_pin(scope, %{"label" => "Companies", "url" => "/companies"})

    owner = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      Bilimbi.Base.Repo.config()[:telemetry_prefix] ++ [:query],
      fn _event, _measurements, metadata, owner ->
        if metadata.source == "user_pins" and match?({:ok, %{command: :select}}, metadata.result) do
          send(owner, :pin_read)
        end
      end,
      owner
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, view, _html} = conn |> log_in_as() |> framed() |> live(~p"/dashboard")
    assert pin_reads() == 0
    refute has_element?(view, "#app-shell[data-pins]")
    refute has_element?(view, "#app-sidebar")

    view |> element("#customize-layout") |> render_click()
    assert pin_reads() == 0
    refute has_element?(view, "#app-shell[data-pins]")
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

  test "a frame's workspace token rides in the same session; a bare page's is ignored", %{
    conn: conn
  } do
    token = "abcdefghijklmnop"

    framed_conn = conn |> log_in_as() |> framed() |> get(~p"/dashboard?ws=#{token}")

    assert FramedRender.session(framed_conn) == %{
             "bilimbi_framed" => true,
             "bilimbi_workspace" => token
           }

    refute Map.has_key?(get_session(framed_conn), "bilimbi_workspace")

    bare_conn = conn |> log_in_as() |> get(~p"/dashboard?ws=#{token}")
    assert FramedRender.session(bare_conn) == %{"bilimbi_framed" => false}

    bad_conn = conn |> log_in_as() |> framed() |> get(~p"/dashboard?ws=nope")
    assert FramedRender.session(bad_conn) == %{"bilimbi_framed" => true}
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
