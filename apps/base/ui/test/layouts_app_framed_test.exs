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

  test "a shell scope renders its pin list, and a missing list is omitted" do
    loaded =
      render_component(&page/1, %{
        current_scope:
          shell_scope(%{pins: [%{id: 1, label: "Companies", url: "/companies", sort_order: 0}]})
      })

    assert loaded =~ ~s(data-pins=)
    assert loaded =~ "/companies"

    empty = render_component(&page/1, %{current_scope: shell_scope(%{pins: []})})
    assert empty =~ ~s(data-pins="[]")

    missing = render_component(&page/1, %{current_scope: shell_scope(%{})})
    refute missing =~ "data-pins"
  end

  defp shell_scope(extra) do
    Map.merge(
      %{
        user: %{
          "name" => "Ada Lovelace",
          "email" => "ada@example.com",
          "company_name" => "Bilimbi Industries"
        },
        scope: %{tenant: %{name: "Bilimbi", id: 41, is_platform_operator: false}},
        shell_preferences: %{
          mode: :local,
          modes: [:company, :local, :utc],
          theme: "system",
          timezone: "Etc/UTC"
        },
        impersonator: nil
      },
      extra
    )
  end
end
