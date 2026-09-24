defmodule Bilimbi.Base.UI.ComponentsStatStripTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp preview(assigns) do
    assigns =
      assigns
      |> Map.put_new(:navigate, nil)
      |> Map.put_new(:kind, :number)

    ~H"""
    <.stat_strip id={@id} title={@title} navigate={@navigate}>
      <:item label="Total" value={@total} />
      <:item label="State" kind={@kind} value="Ready" />
    </.stat_strip>
    """
  end

  defp single_stat(assigns) do
    ~H"""
    <.stat_strip id="storage-stats" title="Storage">
      <:item label="Store" kind={:text} value="Durable" />
    </.stat_strip>
    """
  end

  test "renders a linked strip with multiple numeric and text values" do
    html =
      render_component(&preview/1, %{
        id: "workspace-stats",
        title: "Workspace",
        navigate: "/companies",
        total: 24,
        kind: :text
      })

    assert html =~ ~s(id="workspace-stats")
    assert html =~ ~s(href="/companies")
    assert html =~ "Workspace"
    assert html =~ "Total"
    assert html =~ "24"
    assert html =~ "grid-cols-2"
    assert html =~ "text-xl tabular-nums"
    assert html =~ "text-sm"
  end

  test "renders an unlinked strip as a readable surface" do
    html =
      render_component(&preview/1, %{
        id: "workspace-stats",
        title: "Workspace",
        total: 24
      })

    refute html =~ "href="
    assert html =~ "rounded-xl border border-line bg-surface"
    assert html =~ "Workspace"
  end

  test "supports a single text statistic without link affordance" do
    html = render_component(&single_stat/1, %{})

    assert html =~ ~s(id="storage-stats")
    assert html =~ "grid-cols-1"
    assert html =~ "px-0"
    assert html =~ "Store"
    assert html =~ "Durable"
    assert html =~ "text-sm"
    refute html =~ "href="
  end
end
