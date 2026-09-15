defmodule Bilimbi.Base.UI.LayoutsNavBranchTest do
  @moduledoc """
  Tests for `Layouts.nav_branch/1`, the sidebar rail the shell ships and the
  Design Library renders: leaf rows, branches, the current page, and the
  ancestor accent.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Menu.Item
  alias Bilimbi.Base.UI.Layouts

  defp leaf do
    %{
      item: %Item{
        id: "example.companies",
        label: "Companies",
        icon: "building-office-2",
        route: "/system/design-library/components"
      },
      children: []
    }
  end

  defp branch do
    %{
      item: %Item{id: "example.system", label: "System", icon: "cog-6-tooth"},
      children: [
        %{
          item: %Item{
            id: "example.system.design-library",
            label: "Design Library",
            icon: "paint-brush",
            route: "/system/design-library/components"
          },
          children: []
        }
      ]
    }
  end

  defp render(node, active_nav, opts \\ []) do
    render_component(
      fn assigns ->
        ~H"""
        <Layouts.nav_branch node={@node} active_nav={@active_nav} pinnable={@pinnable} />
        """
      end,
      %{node: node, active_nav: active_nav, pinnable: Keyword.get(opts, :pinnable, true)}
    )
  end

  test "a leaf renders a linked row with its pin control" do
    html = render(leaf(), nil)

    assert html =~ ~s(id="nav-example-companies")
    assert html =~ ~s(href="/system/design-library/components")
    assert html =~ "Companies"
    assert html =~ ~s(data-nav-pin="nav-example-companies")
    refute html =~ ~s(aria-current="page")
  end

  test "pinnable false drops the pin control from every row in the tree" do
    leaf_html = render(leaf(), nil, pinnable: false)
    branch_html = render(branch(), "example.system.design-library", pinnable: false)

    refute leaf_html =~ "data-nav-pin"
    refute branch_html =~ "data-nav-pin"
    assert leaf_html =~ "Companies"
    assert branch_html =~ "Design Library"
  end

  test "the current leaf is marked and accented" do
    html = render(leaf(), "example.companies")

    assert html =~ ~s(aria-current="page")
    assert html =~ "bg-surface text-brand-strong"
  end

  test "a routeless branch renders a toggle rather than a link" do
    html = render(branch(), nil)

    assert html =~ ~s(data-nav-branch="example.system")
    assert html =~ ~s(id="nav-toggle-example-system")
    assert html =~ ~s(aria-label="Toggle System")
    refute html =~ ~s(id="nav-example-system")
  end

  test "a branch holding the current page expands and accents its ancestor" do
    html = render(branch(), "example.system.design-library")

    assert html =~ ~s(data-nav-expanded="true")
    assert html =~ ~s(aria-expanded="true")
    assert html =~ ~s(id="nav-example-system-design-library")
    assert html =~ ~s(aria-current="page")

    [parent, _rest] = String.split(html, "Design Library", parts: 2)
    assert parent =~ "text-brand-strong"
  end

  test "a branch outside the current page stays collapsed" do
    html = render(branch(), "example.companies")

    assert html =~ ~s(data-nav-expanded="false")
    assert html =~ ~s(aria-expanded="false")
    assert html =~ "hidden"
    refute html =~ ~s(aria-current="page")
  end
end
