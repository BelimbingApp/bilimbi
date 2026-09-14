defmodule Bilimbi.Base.UI.ComponentsTabsTest do
  @moduledoc """
  Tests for the shared `<.tabs>` strip: selected, default, disabled, and
  focus-visible states, plus button and link activation.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp link_tabs(assigns) do
    ~H"""
    <.tabs id="example-tabs" aria-label="Example views">
      <:tab href="#overview" current={true}>Overview</:tab>
      <:tab href="#history">History</:tab>
      <:tab disabled={true}>Settings</:tab>
    </.tabs>
    """
  end

  defp button_tabs(assigns) do
    ~H"""
    <.tabs id="settings-tabs" aria-label="Settings groups">
      <:tab
        id="settings-tab-appearance"
        current={true}
        click="switch_tab"
        value="appearance"
      >
        appearance
      </:tab>
      <:tab id="settings-tab-profile" click="switch_tab" value="profile">
        profile
      </:tab>
    </.tabs>
    """
  end

  test "selected, default, and disabled tabs keep their orientation language" do
    html = render_component(&link_tabs/1, %{})

    assert html =~ ~s(id="example-tabs")
    assert html =~ ~s(aria-label="Example views")
    assert html =~ "border-b border-line"
    assert html =~ "Overview"
    assert html =~ "History"
    assert html =~ "Settings"
    assert html =~ "aria-current=\"page\""
    assert html =~ "border-brand-strong font-medium text-ink-strong"
    assert html =~ "border-transparent text-ink-muted hover:text-ink"
    assert html =~ ~s(aria-disabled="true")
    assert html =~ "cursor-not-allowed"
    assert html =~ "opacity-50"
  end

  test "tabs expose a brand-strong focus ring" do
    html = render_component(&link_tabs/1, %{})

    assert html =~ "focus-visible:ring-brand-strong/40"
  end

  test "unlinked tabs render as buttons so in-page switching still works" do
    html = render_component(&button_tabs/1, %{})

    assert html =~ ~s(id="settings-tab-appearance")
    assert html =~ ~s(type="button")
    assert html =~ ~s(phx-click="switch_tab")
    assert html =~ ~s(phx-value-tab="appearance")
    assert html =~ ~s(phx-value-tab="profile")
    refute html =~ ~s(href=")
  end
end
