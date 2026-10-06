defmodule Bilimbi.Base.Grid.ViewTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Grid.View

  test "every field round-trips through URL params, and defaults stay out of the address" do
    params = %{
      "cols" => "name,company.name,employees:count",
      "lens" => "employees:count|bar",
      "z" => "24",
      "since" => "2026-08-01"
    }

    view = View.from_params(params, "users")
    assert view.columns == ~w(name company.name employees:count)
    assert view.lenses == %{"employees:count" => "bar"}
    assert view.zoom == 24
    assert view.since == ~D[2026-08-01] and View.since(view) == ~D[2026-08-01]

    assert View.to_params(view) == %{
             cols: "name,company.name,employees:count",
             lens: "employees:count|bar",
             z: 24,
             since: "2026-08-01"
           }

    assert View.to_params(%View{table: "users"}) == %{}
    assert View.default?(%View{table: "users"})
    refute View.default?(view)
  end

  test "an address carries the view only when it names one of its keys" do
    assert View.carried?(%{"cols" => "name"})
    assert View.carried?(%{"lens" => "a|bar"})
    assert View.carried?(%{"z" => "24"})
    assert View.carried?(%{"since" => "2026-08-01"})
    # The page's own keys say nothing about the columns.
    refute View.carried?(%{"sort" => "name", "page" => "2", "search" => "ada"})
    refute View.carried?(%{})
  end

  test "malformed values fall back rather than raise" do
    view = View.from_params(%{"z" => "huge", "cols" => "", "lens" => "nonsense"}, "users")

    assert view.zoom == 36 and view.columns == [] and view.lenses == %{}
    assert View.from_params(%{"since" => "yesterday"}, "users").since == nil
    assert View.since(%View{}) == Date.add(Date.utc_today(), -30)
    assert View.put_since(%View{since: ~D[2026-01-01]}, "soon").since == nil
  end

  test "a stored map reads back as the same view, and a broken one as the default" do
    view =
      View.from_params(
        %{"cols" => "name,users:count", "lens" => "users:count|band", "z" => "24"},
        "companies"
      )

    assert View.from_map(View.to_map(view), "companies") == view

    assert View.from_map(%{"columns" => "name", "lenses" => [1], "zoom" => "x"}, "companies") ==
             %View{table: "companies", columns: ["name"]}

    assert View.from_map(%{"columns" => [1, "name", "name"], "since" => 3}, "companies") ==
             %View{table: "companies", columns: ["name"]}
  end

  test "the zoom takes only the offered row heights, the nearest to what was asked" do
    # 30 and 33 are heights nothing is drawn at: a row is compact up to 28
    # and normal from 36.
    assert View.from_params(%{"z" => "30"}, "users").zoom == 28
    assert View.from_params(%{"z" => "33"}, "users").zoom == 36
    assert View.from_params(%{"z" => "2"}, "users").zoom == 20
    assert View.from_params(%{"z" => "400"}, "users").zoom == 44
    assert View.put_zoom(%View{}, 24).zoom == 24
  end

  test "reset is the page's own view of the same table" do
    view =
      View.from_params(%{"cols" => "name,users:count", "z" => "24", "since" => "2026-08-01"}, "t")

    assert View.reset(view) == %View{table: "t"}
    assert View.default?(View.reset(view))
  end

  test "removing a column drops its lens, and moving one keeps the rest in order" do
    view = %View{columns: ~w(a b c), lenses: %{"b" => "bar"}}

    assert View.remove_column(view, "b") == %View{columns: ~w(a c), lenses: %{}}
    assert View.move_column(view, "c", "a").columns == ~w(c a b)
    assert View.move_column(view, "a", nil).columns == ~w(b c a)
    assert View.add_column(view, "a") == view
    assert View.put_lens(view, "b", "value").lenses == %{}
  end
end
