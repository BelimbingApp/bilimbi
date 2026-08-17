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

    ~H"""
    <.table id="people" rows={@rows} sort_by={@sort_by} sort_dir={@sort_dir} framed={@framed}>
      <:col :let={row} label="Name" sort="name" sort_id="people-sort-name">{row.name}</:col>
      <:col :let={row} label="Note">{row.note}</:col>
      <:empty :if={@rows == []}>Nobody here.</:empty>
    </.table>
    """
  end

  test "marks the active sort column for assistive tech" do
    html = render_component(&preview/1, %{rows: [%{name: "Ada", note: "ok"}]})

    assert html =~ ~s(aria-sort="ascending")
    assert html =~ ~s(id="people-sort-name")
    assert html =~ ~s(phx-click="sort")
    assert html =~ ~s(phx-value-sort="name")
    assert html =~ "Ada"
    refute html =~ "Nobody here."
  end

  test "keeps empty copy out of the stream tbody" do
    html = render_component(&preview/1, %{rows: []})

    assert html =~ "Nobody here."
    assert html =~ ~s(id="people-empty")
  end

  test "omits card chrome when nested in an existing panel" do
    html =
      render_component(&preview/1, %{
        rows: [%{name: "Ada", note: "ok"}],
        framed: false
      })

    refute html =~ "rounded-xl border border-line bg-surface"
  end
end
