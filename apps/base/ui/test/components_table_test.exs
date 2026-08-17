defmodule Bilimbi.Base.UI.ComponentsTableTest do
  @moduledoc """
  The shared table is the density and sort contract. Screens that rebuild
  `<table>` by hand miss both, so these lock the primitive itself.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp preview(assigns) do
    assigns =
      assigns
      |> Map.put_new(:sort_by, "name")
      |> Map.put_new(:sort_dir, "asc")
      |> Map.put_new(:framed, true)
      |> Map.put_new(:caption, nil)
      |> Map.put_new(:sort_event, "sort")
      |> Map.put_new(:sort_id, "people-sort-name")

    ~H"""
    <.table
      id="people"
      rows={@rows}
      sort_by={@sort_by}
      sort_dir={@sort_dir}
      framed={@framed}
      caption={@caption}
      sort_event={@sort_event}
    >
      <:col :let={row} label="Name" sort="name" sort_id={@sort_id}>{row.name}</:col>
      <:col :let={row} label="Count" sort="count" sort_id="people-sort-count" align={:right}>
        {row.count}
      </:col>
      <:col :let={row} label="Note">{row.note}</:col>
      <:empty :if={@rows == []}>Nobody here.</:empty>
    </.table>
    """
  end

  test "marks the active sort column for assistive tech" do
    html = render_component(&preview/1, %{rows: [%{name: "Ada", note: "ok", count: 3}]})

    assert html =~ ~s(aria-sort="ascending")
    assert html =~ ~s(id="people-sort-name")
    assert html =~ ~s(phx-click="sort")
    assert html =~ ~s(phx-value-sort="name")
    assert html =~ "Ada"
    refute html =~ "Nobody here."
  end

  test "derives a stable sort button ID when the caller omits one" do
    html =
      render_component(&preview/1, %{
        rows: [%{name: "Ada", note: "ok", count: 3}],
        sort_id: nil
      })

    assert html =~ ~s(id="people-sort-name")
  end

  test "keeps empty copy out of the stream tbody" do
    html = render_component(&preview/1, %{rows: []})

    assert html =~ "Nobody here."
    assert html =~ ~s(id="people-empty")
  end

  test "omits card chrome when nested in an existing panel" do
    html =
      render_component(&preview/1, %{
        rows: [%{name: "Ada", note: "ok", count: 3}],
        framed: false
      })

    refute html =~ "rounded-xl border border-line bg-surface"
  end

  test "names the table with an sr-only caption" do
    html =
      render_component(&preview/1, %{
        rows: [%{name: "Ada", note: "ok", count: 3}],
        caption: "People"
      })

    assert html =~ ~s(<caption class="sr-only">People</caption>)
  end

  test "right-aligns numeric columns on header and cell" do
    html = render_component(&preview/1, %{rows: [%{name: "Ada", note: "ok", count: 3}]})

    assert html =~ "text-right"
    assert html =~ "ml-auto"
    assert html =~ "people-sort-count"
  end

  test "sort_event overrides the default phx-click name" do
    html =
      render_component(&preview/1, %{
        rows: [%{name: "Ada", note: "ok", count: 3}],
        sort_event: "sort-summary"
      })

    assert html =~ ~s(phx-click="sort-summary")
  end
end
