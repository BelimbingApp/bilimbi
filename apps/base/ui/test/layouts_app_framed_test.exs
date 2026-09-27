defmodule Bilimbi.Base.UI.LayoutsAppFramedTest do
  @moduledoc """
  `Layouts.app/1` renders chromeless when the scope is marked framed: the
  page's content, its flash, and the one element `<.datetime>` reads the
  clock from, and nothing a workspace tile would duplicate.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.UI.Layouts

  defp page(assigns) do
    ~H"""
    <Layouts.app flash={%{}} current_scope={@current_scope} active_nav={nil}>
      <p id="page-body">Framed content</p>
    </Layouts.app>
    """
  end

  test "a framed scope gets only the content and the flash outlet" do
    html =
      render_component(&page/1, %{
        current_scope: %{framed: true, shell_preferences: %{mode: "local", theme: "system"}}
      })

    assert html =~ ~s(id="app-shell")
    assert html =~ ~s(data-framed="true")
    assert html =~ ~s(data-display-mode="local")
    assert html =~ ~s(id="app-content")
    assert html =~ ~s(id="page-body")
    assert html =~ ~s(id="flash-group")
    refute html =~ ~s(id="app-topbar")
    refute html =~ ~s(id="app-sidebar")
    refute html =~ ~s(id="app-statusbar")
  end
end
