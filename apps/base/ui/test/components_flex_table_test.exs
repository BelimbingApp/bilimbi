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
      |> assign_new(:mode, fn -> :normal end)
      |> assign_new(:cost, fn -> nil end)
      |> assign_new(:since, fn -> nil end)
      |> assign(:rows, @rows)

    ~H"""
    <.flex_table
      id="costed-grid"
      columns={@columns}
      rows={@rows}
      mode={@mode}
      cost={@cost}
      since={@since}
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

  test "one toggle switches between normal and compact rows, and says which is on" do
    normal = render_component(&grid/1, %{})
    toggle = tag(normal, "costed-grid-density")

    assert tag(normal, "costed-grid") =~ ~s(data-mode="normal")
    assert toggle =~ ~s(aria-label="Compact rows")
    assert toggle =~ ~s(aria-pressed="false")
    assert toggle =~ ~s(title="Normal rows are on. Switch to compact rows.")
    assert toggle =~ ~s(phx-value-op="density")
    assert toggle =~ ~s(phx-value-density="compact")

    compact = render_component(&grid/1, %{mode: :compact})
    toggle = tag(compact, "costed-grid-density")

    assert tag(compact, "costed-grid") =~ ~s(data-mode="compact")
    assert toggle =~ ~s(aria-label="Compact rows")
    assert toggle =~ ~s(aria-pressed="true")
    assert toggle =~ ~s(title="Compact rows are on. Switch to normal rows.")
    assert toggle =~ ~s(phx-value-density="normal")
  end

  test "table customization is a panel behind a settings icon, closed until asked for" do
    html = render_component(&grid/1, %{})
    customize = tag(html, "costed-grid-customize")
    controls = tag(html, "costed-grid-controls")
    panel = tag(html, "costed-grid-customization")

    assert customize =~ ~s(aria-label="Customize table")
    assert customize =~ ~s(title="Customize table")
    assert customize =~ ~s(aria-expanded="false")
    assert customize =~ ~s(aria-controls="costed-grid-customization")

    # Open is the icon's `aria-expanded` and nothing else: the panel shows
    # by reading it, so a patch that redraws the chips cannot close it.
    assert [["toggle_attr", %{"attr" => ["aria-expanded", "true", "false"]}]] =
             js(customize, "phx-click")

    assert panel =~ ~s(aria-label="Table customization")
    assert "hidden" in classes(panel)
    assert "peer-aria-expanded:block" in classes(panel)
    assert "floating-panel" in classes(panel)

    # A click outside closes it; Escape closes it and returns focus to the
    # icon; focus leaving alone does not, since removing a chip is that.
    assert [["set_attr", %{"to" => "#costed-grid-customize"}]] = js(controls, "phx-click-away")

    assert [["set_attr", _], ["focus", %{"to" => "#costed-grid-customize"}]] =
             js(controls, "data-escape")

    assert controls =~ "data-keep-on-blur"
    assert controls =~ ~s(phx-hook="DisclosureDismiss")

    # The chips and the add box live in the panel; the density toggle does not.
    [_, inside] = String.split(html, ~s(id="costed-grid-customization"), parts: 2)
    [inside, _table] = String.split(inside, ~s(id="costed-grid-viewport"), parts: 2)
    assert inside =~ ~s(id="costed-grid-chip-code")
    assert inside =~ ~s(id="costed-grid-add-column-input")
    refute inside =~ ~s(id="costed-grid-density")
  end

  test "compact is the same table with tighter rows that stay on one line" do
    normal = render_component(&grid/1, %{})
    compact = render_component(&grid/1, %{mode: :compact})

    # Both are a table of the same rows, cells and row actions.
    for html <- [normal, compact] do
      assert html =~ ~s(<table)
      assert html =~ ~s(id="costed-grid-row-1")
      assert html =~ ~s(id="costed-grid-cell-1-code")
      assert html =~ ~s(id="open-1")
      refute html =~ "<canvas"
    end

    assert tag(compact, "costed-grid-cell-1-code") =~ "whitespace-nowrap"
    assert tag(compact, "costed-grid-cell-1-code") =~ "py-0 "
    refute tag(normal, "costed-grid-cell-1-code") =~ "whitespace-nowrap"
  end

  test "the comparison date shows only while a column wears the change-since lens" do
    delta = Enum.map(@columns, &%{&1 | lens: :delta, lenses: [:value, :delta]})

    html = render_component(&grid/1, %{columns: delta, since: ~D[2026-08-01]})
    assert tag(html, "costed-grid-since-input") =~ ~s(value="2026-08-01")
    assert tag(html, "costed-grid-since-input") =~ ~s(type="date")

    refute render_component(&grid/1, %{since: ~D[2026-08-01]}) =~ "costed-grid-since"
  end
end
