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

    assert {:patch, %View{density: :compact}} =
             Host.apply(%{"op" => "density", "density" => "compact"}, view, [])

    assert {:patch, %View{density: :normal}} =
             Host.apply(
               %{"op" => "density", "density" => "anything else"},
               %{view | density: :compact},
               []
             )

    assert {:patch, %View{since: ~D[2026-08-01]}} =
             Host.apply(%{"op" => "since", "since" => "2026-08-01"}, view, [])

    assert {:patch, %View{since: nil}} =
             Host.apply(%{"op" => "since", "since" => "never"}, view, [])

    assert Host.apply(%{"op" => "sort", "sort" => "name"}, view, []) == :noop
    assert Host.apply(%{"op" => "zoom", "dir" => "in"}, view, []) == :noop
  end
end
