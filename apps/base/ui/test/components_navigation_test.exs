defmodule Bilimbi.Base.UI.ComponentsNavigationTest do
  @moduledoc """
  Tests for the shared `<.navigation>` list: parent, current, pinned, and
  disabled items, plus keyboard focus rings.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp nav(assigns) do
    ~H"""
    <.navigation id="example-nav" aria-label="Example menu">
      <:item href="#companies">Companies</:item>
      <:item href="#system" ancestor={true}>System</:item>
      <:item href="#library" current={true} nested={true}>Design Library</:item>
      <:item href="#pinned" pinned={true}>Pinned item</:item>
      <:item disabled={true}>Disabled</:item>
    </.navigation>
    """
  end

  test "renders a labelled nav with parent, current, pinned, and disabled items" do
    html = render_component(&nav/1, %{})

    assert html =~ ~s(id="example-nav")
    assert html =~ ~s(aria-label="Example menu")
    assert html =~ "bg-surface-sidebar"
    assert html =~ "text-[0.8125rem]"
    assert html =~ "Companies"
    assert html =~ "System"
    assert html =~ "Design Library"
    assert html =~ "Pinned item"
    assert html =~ "Disabled"
  end

  test "the current item uses surface and brand-strong orientation" do
    html = render_component(&nav/1, %{})

    assert html =~ "aria-current=\"page\""
    assert html =~ "bg-surface text-brand-strong"
    refute html =~ "font-bold"
  end

  test "the ancestor uses brand-strong without a selected surface" do
    html = render_component(&nav/1, %{})

    assert html =~ "text-brand-strong hover:bg-surface-muted"
    assert html =~ "&#x2BC6;"
  end

  test "the pinned item sits on the brand surface" do
    html = render_component(&nav/1, %{})

    assert html =~ "bg-brand-surface"
  end

  test "disabled items are not links and announce as disabled" do
    html = render_component(&nav/1, %{})

    assert html =~ ~s(aria-disabled="true")
    assert html =~ "cursor-not-allowed"
    assert html =~ "opacity-50"
    refute html =~ ~s(href="#disabled")
  end

  test "items expose a brand-strong focus ring" do
    html = render_component(&nav/1, %{})

    assert html =~ "focus-visible:ring-brand-strong/40"
    assert html =~ "rounded-sm"
  end
end
