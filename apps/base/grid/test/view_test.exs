defmodule Bilimbi.Base.Grid.ViewTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Grid.View

  test "every field round-trips through URL params, and defaults stay out of the address" do
    params = %{
      "cols" => "name,company.name,employees:count",
      "lens" => "employees:count|bar",
      "z" => "12",
      "sort" => "employees:count",
      "dir" => "desc",
      "q" => "acme",
      "page" => "2",
      "per_page" => "50",
      "group" => "status",
      "follow" => "company",
      "focus" => "73",
      "since" => "2026-08-01",
      "v" => "desk"
    }

    view = View.from_params(params, "users")
    assert view.columns == ~w(name company.name employees:count)
    assert view.lenses == %{"employees:count" => "bar"}
    assert view.zoom == 12 and view.sort == "employees:count" and view.dir == :desc
    assert view.search == "acme" and view.page == 2 and view.page_size == 50
    assert view.group == "status" and view.follow == "company" and view.focus == "73"
    assert view.since == ~D[2026-08-01] and View.since(view) == ~D[2026-08-01]
    assert view.slug == "desk"

    assert View.to_params(view) == %{
             cols: "name,company.name,employees:count",
             lens: "employees:count|bar",
             z: 12,
             sort: "employees:count",
             dir: "desc",
             q: "acme",
             page: 2,
             per_page: 50,
             group: "status",
             follow: "company",
             focus: "73",
             since: "2026-08-01",
             v: "desk"
           }

    assert View.to_params(%View{table: "users"}) == %{}
  end

  test "malformed values fall back rather than raise" do
    view =
      View.from_params(
        %{
          "z" => "huge",
          "page" => "-1",
          "per_page" => "7",
          "follow" => "Bad One",
          "focus" => "a/b",
          "dir" => "up"
        },
        "users"
      )

    assert view.zoom == 28 and view.page == 1 and view.page_size == 25
    assert view.follow == nil and view.focus == nil and view.dir == :asc
    assert View.from_params(%{"since" => "yesterday"}, "users").since == nil
    assert View.since(%View{}) == Date.add(Date.utc_today(), -30)
  end

  test "a saved map keeps the follow but never the selected record" do
    view =
      View.from_params(
        %{"follow" => "company", "focus" => "73", "cols" => "name", "since" => "2026-08-01"},
        "users"
      )

    map = View.to_map(view)
    assert map["follow"] == "company" and map["since"] == "2026-08-01"
    assert View.from_map(map).since == ~D[2026-08-01]
    refute Map.has_key?(map, "focus")
    restored = View.from_map(map)
    assert restored.follow == "company" and restored.focus == nil and restored.columns == ["name"]
  end
end
