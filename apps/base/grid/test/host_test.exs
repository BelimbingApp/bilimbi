defmodule Bilimbi.Base.Grid.Web.HostTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Grid.View
  alias Bilimbi.Base.Grid.Web.Host

  test "nothing estimated carries no cost" do
    assert Host.cost(nil) == nil
  end

  test "a cost is heavy only above the threshold" do
    assert Host.cost(20_000.0) == %{estimate: 20_000.0, heavy?: false}
    assert Host.cost(20_001.0) == %{estimate: 20_001.0, heavy?: true}
  end

  test "an op changes the view, and the page's own sort never arrives" do
    view = %View{table: "users", columns: ["name"]}

    assert {:patch, %View{columns: ["name", "company.name"]}} =
             Host.apply(%{"op" => "add", "spec" => "company.name"}, view, [])

    assert {:patch, %View{columns: []}} =
             Host.apply(%{"op" => "remove", "spec" => "name"}, view, [])

    assert {:patch, %View{since: ~D[2026-08-01]}} =
             Host.apply(%{"op" => "since", "since" => "2026-08-01"}, view, [])

    assert {:patch, %View{since: nil}} =
             Host.apply(%{"op" => "since", "since" => "never"}, view, [])

    assert {:patch, %View{table: "users", columns: [], zoom: 36}} =
             Host.apply(%{"op" => "reset"}, %{view | zoom: 24}, [])

    assert Host.apply(%{"op" => "sort", "sort" => "name"}, view, []) == :noop
  end

  test "the zoom steps through the offered heights and stops at either end" do
    view = %View{table: "users"}
    step = fn view, dir -> Host.apply(%{"op" => "zoom", "dir" => dir}, view, []) end

    assert {:patch, %View{zoom: 40}} = step.(view, "in")
    # Out of normal rows the next height down is the tallest compact one.
    assert {:patch, %View{zoom: 28}} = step.(view, "out")
    assert {:patch, %View{zoom: 44}} = step.(%{view | zoom: 44}, "in")
    assert {:patch, %View{zoom: 20}} = step.(%{view | zoom: 20}, "out")
  end

  test "a preset names the height it sets, so pressing it twice lands on the same rows" do
    view = %View{table: "users"}
    preset = fn view, name -> Host.apply(%{"op" => "zoom_preset", "preset" => name}, view, []) end

    assert {:patch, %View{zoom: 24} = compact} = preset.(view, "compact")
    assert {:patch, ^compact} = preset.(compact, "compact")
    assert {:patch, %View{zoom: 36}} = preset.(compact, "normal")
    # From any compact height, not only the preset's own.
    assert {:patch, %View{zoom: 36}} = preset.(%{view | zoom: 20}, "normal")
    assert preset.(view, "huge") == :noop
  end
end
