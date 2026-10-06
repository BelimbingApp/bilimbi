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
    assigns = assign(assigns, columns: @columns, rows: @rows)

    ~H"""
    <.flex_table id="costed-grid" columns={@columns} rows={@rows} total={1} cost={@cost} />
    """
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
end
