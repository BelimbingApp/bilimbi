defmodule Bilimbi.Base.UI.ComponentsFlexTableTest do
  use ExUnit.Case, async: true

  use Bilimbi.Base.UI.Components

  import Phoenix.Component
  import Phoenix.LiveViewTest

  @columns [
    %{
      id: "code",
      spec: "code",
      label: "Code",
      short_label: "Code",
      type: :string,
      kind: :field,
      lens: :value,
      lenses: [:value, :band],
      sortable: true,
      removable: true,
      align: nil
    }
  ]

  @rows [
    %{
      key: 1,
      cells: %{
        "code" => %{
          text: "ACME",
          value: "ACME",
          n: nil,
          band: nil,
          scale: nil,
          series: nil,
          delta: nil
        }
      }
    }
  ]

  defp grid(assigns) do
    assigns =
      assigns
      |> assign_new(:columns, fn -> @columns end)
      |> assign_new(:zoom, fn -> 32 end)
      |> assign_new(:cost, fn -> nil end)
      |> assign_new(:since, fn -> nil end)
      |> assign_new(:expanded, fn -> %{} end)
      |> assign(:rows, @rows)

    ~H"""
    <.flex_table
      id="costed-grid"
      columns={@columns}
      rows={@rows}
      mode={Bilimbi.Base.UI.FlexTable.mode(@zoom)}
      zoom={@zoom}
      cost={@cost}
      since={@since}
      expanded={@expanded}
    >
      <:action :let={row}>
        <.icon_button icon="view" id={"open-#{row.key}"} label="Open" />
      </:action>
    </.flex_table>
    """
  end

  defp classes(tag) do
    [class] = Regex.run(~r/\sclass="([^"]*)"/, tag, capture: :all_but_first)
    String.split(class)
  end

  # The JS command an attribute carries, decoded as the client reads it.
  defp js(tag, attr) do
    [encoded] = Regex.run(~r/\s#{attr}="([^"]*)"/, tag, capture: :all_but_first)
    encoded |> String.replace("&quot;", "\"") |> JSON.decode!()
  end

  defp tag(html, id) do
    [tag] = Regex.run(~r/<[a-z]+[^>]*\sid="#{id}"[^>]*>/, html)
    tag
  end

  # The warning paragraph as rendered, or nil when there is none.
  defp cost_warning(html) do
    case Regex.run(~r/<p[^>]*id="costed-grid-cost"[^>]*>(.*?)<\/p>/s, html) do
      [_, body] -> body
      nil -> nil
    end
  end

  test "a heavy planner cost warns above the table with the truncated estimate" do
    html = render_component(&grid/1, %{cost: %{estimate: 32_000.0, heavy?: true}})

    warning = cost_warning(html)
    assert warning =~ "Heavy query"
    assert warning =~ "32000"
    refute warning =~ "32000.0"
  end

  test "a light cost or no cost shows no warning" do
    for cost <- [%{estimate: 500.0, heavy?: false}, nil] do
      html = render_component(&grid/1, %{cost: cost})

      assert html =~ ~s(id="costed-grid")
      assert cost_warning(html) == nil
    end
  end

  test "a lip on the table's edge opens table customization, closed until asked for" do
    html = render_component(&grid/1, %{})
    lip = tag(html, "costed-grid-customize")
    wrap = tag(html, "costed-grid-customizing")
    bar = tag(html, "costed-grid-customization")

    assert lip =~ ~s(aria-label="Customize table")
    assert lip =~ ~s(title="Customize table")
    assert lip =~ ~s(aria-expanded="false")
    assert lip =~ ~s(aria-controls="costed-grid-customization")
    assert lip =~ ~s(type="button")

    # Open is the lip's `aria-expanded` and nothing else: the bar shows by
    # reading it, so a patch that redraws the chips cannot close it.
    assert [["toggle_attr", %{"attr" => ["aria-expanded", "true", "false"]}]] =
             js(lip, "phx-click")

    assert bar =~ ~s(aria-label="Table customization")
    assert "hidden" in classes(bar)
    assert "peer-aria-expanded:flex" in classes(bar)

    # Escape closes it and returns focus to the lip. Focus leaving does not,
    # since removing a chip is that, and neither does a click elsewhere: the
    # bar is part of the page, not a popover over it.
    assert [["set_attr", _], ["focus", %{"to" => "#costed-grid-customize"}]] =
             js(wrap, "data-escape")

    assert wrap =~ "data-keep-on-blur"
    assert wrap =~ ~s(phx-hook="DisclosureDismiss")
    refute wrap =~ "phx-click-away"

    # The lip and the bar come before the table, and the bar holds the chips,
    # the add box, the zoom and the reset.
    [before_table, _table] = String.split(html, ~s(id="costed-grid-viewport"), parts: 2)
    [_lip, inside] = String.split(before_table, ~s(id="costed-grid-customization"), parts: 2)
    assert inside =~ ~s(id="costed-grid-chip-code")
    assert inside =~ ~s(id="costed-grid-add-column-input")
    assert inside =~ ~s(id="costed-grid-zoom")
    assert tag(html, "costed-grid-reset") =~ ~s(phx-value-op="reset")
  end

  test "the frame and its scroll box carry the marks a workspace tile fills from" do
    html = render_component(&grid/1, %{})

    # The "list fill" rules in app.css give a `data-table-region` the room a
    # tile has left and stick its heading row; the frame around it is how
    # they find one that has the lip and the bar above it.
    assert tag(html, "costed-grid") =~ "data-table-frame"
    assert tag(html, "costed-grid-viewport") =~ "data-table-region"

    # The scroll box is the frame's own child, after the lip and the bar.
    assert html =~
             ~r/id="costed-grid-customization".*<\/div>\s*<\/div>\s*<div[^>]*id="costed-grid-viewport"/s

    # A positioned scroll box: an `sr-only` caption inside it would otherwise
    # be laid out against the document and grow a second scrollbar.
    assert "relative" in classes(tag(html, "costed-grid-viewport"))
  end

  test "the zoom steps only through heights that change the table, and names two of them" do
    normal = render_component(&grid/1, %{})

    assert tag(normal, "costed-grid") =~ ~s(data-zoom="32")
    assert tag(normal, "costed-grid") =~ ~s(data-mode="normal")
    assert normal =~ ~r/id="costed-grid-zoom-level"[^>]*>\s*32 px\s*</
    assert tag(normal, "costed-grid-zoom-normal") =~ ~s(aria-pressed="true")
    assert tag(normal, "costed-grid-zoom-compact") =~ ~s(aria-pressed="false")
    assert "h-8" in classes(tag(normal, "costed-grid-cell-1-code"))

    # Each press is pushed by the hook from these, never dropped by LiveView's
    # guard on a click still awaiting its reply.
    assert tag(normal, "costed-grid-zoom-in") =~ ~s(data-zoom-op="zoom")
    assert tag(normal, "costed-grid-zoom-in") =~ ~s(data-dir="in")
    assert tag(normal, "costed-grid-zoom-compact") =~ ~s(data-zoom-op="zoom_preset")
    assert tag(normal, "costed-grid-zoom-compact") =~ ~s(data-preset="compact")
    refute tag(normal, "costed-grid-zoom-in") =~ "phx-click"
    refute tag(normal, "costed-grid-zoom-compact") =~ "phx-click"

    # The ends of the range are disabled steps, not steps that do nothing.
    shortest = render_component(&grid/1, %{zoom: 18})
    assert tag(shortest, "costed-grid-zoom-out") =~ ~r/\sdisabled[\s>]/
    refute tag(shortest, "costed-grid-zoom-in") =~ ~r/\sdisabled[\s>]/
    assert tag(shortest, "costed-grid-zoom-compact") =~ ~s(aria-pressed="true")
    assert "h-4.5" in classes(tag(shortest, "costed-grid-cell-1-code"))

    tallest = render_component(&grid/1, %{zoom: 40})
    assert tag(tallest, "costed-grid-zoom-in") =~ ~r/\sdisabled[\s>]/
    refute tag(tallest, "costed-grid-zoom-out") =~ ~r/\sdisabled[\s>]/
  end

  test "every offered height has a row class of its own and a mode" do
    steps = Bilimbi.Base.UI.FlexTable.zoom_steps()

    assert steps == Enum.sort(steps)

    assert steps |> Enum.map(&Bilimbi.Base.UI.FlexTable.row_class/1) |> Enum.uniq() |> length() ==
             length(steps)

    assert Enum.map(steps, &Bilimbi.Base.UI.FlexTable.mode/1) ==
             [:compact, :compact, :compact, :normal, :normal, :normal]

    # A height nothing is drawn at is the nearest one that is.
    assert Bilimbi.Base.UI.FlexTable.normalize_zoom(30) == 32
    assert Bilimbi.Base.UI.FlexTable.normalize_zoom("27") == 26
    assert Bilimbi.Base.UI.FlexTable.normalize_zoom(nil) == 32
    assert Bilimbi.Base.UI.FlexTable.step_zoom(26, :in) == 32
    assert Bilimbi.Base.UI.FlexTable.step_zoom(40, :in) == 40
    assert Bilimbi.Base.UI.FlexTable.step_zoom(18, :out) == 18
    assert Bilimbi.Base.UI.FlexTable.zoom_presets() == [compact: 18, normal: 32]
  end

  test "compact is the same table with tighter rows that stay on one line" do
    normal = render_component(&grid/1, %{})
    compact = render_component(&grid/1, %{zoom: 24})

    # Both are a table of the same rows, cells and row actions.
    for html <- [normal, compact] do
      assert html =~ ~s(<table)
      assert html =~ ~s(id="costed-grid-row-1")
      assert html =~ ~s(id="costed-grid-cell-1-code")
      assert html =~ ~s(id="open-1")
      refute html =~ "<canvas"
    end

    assert tag(compact, "costed-grid") =~ ~s(data-mode="compact")
    assert "whitespace-nowrap" in classes(tag(compact, "costed-grid-cell-1-code"))
    assert "py-0" in classes(tag(compact, "costed-grid-cell-1-code"))
    refute "whitespace-nowrap" in classes(tag(normal, "costed-grid-cell-1-code"))
  end

  test "the comparison date shows only while a column wears the change-since lens" do
    delta = Enum.map(@columns, &%{&1 | lens: :delta, lenses: [:value, :delta]})

    html = render_component(&grid/1, %{columns: delta, since: ~D[2026-08-01]})
    assert tag(html, "costed-grid-since-input") =~ ~s(value="2026-08-01")
    assert tag(html, "costed-grid-since-input") =~ ~s(type="date")

    refute render_component(&grid/1, %{since: ~D[2026-08-01]}) =~ "costed-grid-since"
  end

  test "a timestamp among a rollup's expanded rows follows the reader's clock" do
    opened = %{
      1 => %{
        "code" => [%{"Name" => "Ada", "Created" => ~N[2026-10-05 13:22:10], "Active" => true}]
      }
    }

    html = render_component(&grid/1, %{expanded: opened})

    # Drawn by `datetime/1`, as a walked cell's timestamp is, never as the
    # raw UTC text of the value.
    assert html =~ ~s(<time)
    assert html =~ ~s(id="costed-grid-row-1-code-0-)
    refute html =~ "2026-10-05 13:22:10"
    assert html =~ "Ada"
    assert html =~ "Yes"
  end
end
