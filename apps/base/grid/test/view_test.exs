defmodule Bilimbi.Base.Grid.ViewTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Grid.View

  test "every field round-trips through URL params, and defaults stay out of the address" do
    params = %{
      "cols" => "name,company.name,employees:count",
      "lens" => "employees:count|bar",
      "density" => "compact",
      "since" => "2026-08-01"
    }

    view = View.from_params(params, "users")
    assert view.columns == ~w(name company.name employees:count)
    assert view.lenses == %{"employees:count" => "bar"}
    assert view.density == :compact
    assert view.since == ~D[2026-08-01] and View.since(view) == ~D[2026-08-01]

    assert View.to_params(view) == %{
             cols: "name,company.name,employees:count",
             lens: "employees:count|bar",
             density: "compact",
             since: "2026-08-01"
           }

    assert View.to_params(%View{table: "users"}) == %{}
    assert View.default?(%View{table: "users"})
    refute View.default?(view)
  end

  test "an address carries the view only when it names one of its keys" do
    assert View.carried?(%{"cols" => "name"})
    assert View.carried?(%{"lens" => "a|bar"})
    assert View.carried?(%{"density" => "compact"})
    assert View.carried?(%{"since" => "2026-08-01"})
    # The page's own keys say nothing about the columns.
    refute View.carried?(%{"sort" => "name", "page" => "2", "search" => "ada"})
    refute View.carried?(%{})
  end

  test "malformed values fall back rather than raise" do
    view = View.from_params(%{"density" => "tiny", "cols" => "", "lens" => "nonsense"}, "users")

    assert view.density == :normal and view.columns == [] and view.lenses == %{}
    assert View.from_params(%{"since" => "yesterday"}, "users").since == nil
    assert View.since(%View{}) == Date.add(Date.utc_today(), -30)
    assert View.put_since(%View{since: ~D[2026-01-01]}, "soon").since == nil
  end

  test "a stored map reads back as the same view, and a broken one as the default" do
    view =
      View.from_params(
        %{"cols" => "name,users:count", "lens" => "users:count|band", "density" => "compact"},
        "companies"
      )

    assert View.from_map(View.to_map(view), "companies") == view

    assert View.from_map(%{"columns" => "name", "lenses" => [1], "density" => 7}, "companies") ==
             %View{table: "companies", columns: ["name"]}

    assert View.from_map(%{"columns" => [1, "name", "name"], "since" => 3}, "companies") ==
             %View{table: "companies", columns: ["name"]}
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
