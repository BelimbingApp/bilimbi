defmodule Bilimbi.Base.Tiling.LayoutTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Tiling.Layout

  defp open!(layout, path, opts \\ []) do
    {:ok, layout, id} = Layout.open(layout, path, opts)
    {layout, id}
  end

  defp paths(layout), do: layout |> Layout.leaves() |> Enum.map(& &1.path)

  defp rect(layout, id) do
    layout
    |> Layout.rects()
    |> Map.fetch!(:leaves)
    |> Enum.find(fn {leaf, _} -> leaf.id == id end)
    |> elem(1)
  end

  describe "open/3" do
    test "the first page fills an empty workspace" do
      {layout, id} = open!(Layout.empty(), "/companies")

      assert Layout.count(layout) == 1
      assert rect(layout, id) == %{x: 0.0, y: 0.0, w: 1.0, h: 1.0}
      assert Layout.encode(layout) == "/companies"
    end

    test "a landscape tile splits side by side and a portrait tile top and bottom" do
      {layout, first} = open!(Layout.empty(), "/companies")
      {layout, second} = open!(layout, "/users", at: first, viewport: {1600, 900})

      assert rect(layout, first) == %{x: 0.0, y: 0.0, w: 0.5, h: 1.0}
      assert rect(layout, second) == %{x: 0.5, y: 0.0, w: 0.5, h: 1.0}

      {layout, third} = open!(layout, "/employees", at: second, viewport: {1600, 900})

      # The right half is 800 by 900 pixels, taller than wide.
      assert rect(layout, second) == %{x: 0.5, y: 0.0, w: 0.5, h: 0.5}
      assert rect(layout, third) == %{x: 0.5, y: 0.5, w: 0.5, h: 0.5}
      assert Layout.encode(layout) == "h.5(/companies,v.5(/users,/employees))"
    end

    test "splits the last tile when no target is given" do
      {layout, _} = open!(Layout.empty(), "/companies")
      {layout, _} = open!(layout, "/users")
      {layout, _} = open!(layout, "/employees")

      assert Layout.encode(layout) == "h.5(/companies,v.5(/users,/employees))"
    end

    test "refuses a seventh tile" do
      layout =
        Enum.reduce(1..6, Layout.empty(), fn n, layout ->
          {layout, _} = open!(layout, "/page/#{n}")
          layout
        end)

      assert Layout.full?(layout)
      assert Layout.open(layout, "/page/7") == {:error, :full}
    end
  end

  describe "close/2" do
    test "the sibling takes the closed tile's room" do
      {layout, a} = open!(Layout.empty(), "/companies")
      {layout, b} = open!(layout, "/users", at: a)
      {layout, c} = open!(layout, "/employees", at: b)

      layout = Layout.close(layout, b)

      assert paths(layout) == ["/companies", "/employees"]
      assert rect(layout, c) == %{x: 0.5, y: 0.0, w: 0.5, h: 1.0}
      assert Layout.close(layout, "nope") == layout
    end

    test "closing the only tile empties the workspace" do
      {layout, a} = open!(Layout.empty(), "/companies")

      assert Layout.empty?(Layout.close(layout, a))
    end
  end

  describe "resize" do
    test "resize/3 clamps the ratio" do
      {layout, a} = open!(Layout.empty(), "/companies")
      {layout, _} = open!(layout, "/users", at: a)
      [{split, _}] = Layout.rects(layout).handles

      assert Layout.encode(Layout.resize(layout, split.id, 0.7)) == "h.7(/companies,/users)"
      assert Layout.encode(Layout.resize(layout, split.id, 0.01)) == "h.1(/companies,/users)"
      assert Layout.encode(Layout.resize(layout, split.id, 2)) == "h.9(/companies,/users)"
    end

    test "nudge/3 moves one divider along its own axis only" do
      {layout, a} = open!(Layout.empty(), "/companies")
      {layout, _} = open!(layout, "/users", at: a)
      [{split, rect}] = Layout.rects(layout).handles

      assert rect == %{x: 0.0, y: 0.0, w: 1.0, h: 1.0}
      assert Layout.encode(Layout.nudge(layout, split.id, :left)) == "h.45(/companies,/users)"
      assert Layout.nudge(layout, split.id, :up) == layout
      assert Layout.nudge(layout, "nope", :left) == layout
    end

    test "resize_step/3 moves the nearest divider on that axis" do
      {layout, a} = open!(Layout.empty(), "/companies")
      {layout, b} = open!(layout, "/users", at: a)
      {layout, c} = open!(layout, "/employees", at: b)

      assert Layout.encode(Layout.resize_step(layout, c, :right)) ==
               "h.55(/companies,v.5(/users,/employees))"

      assert Layout.encode(Layout.resize_step(layout, c, :up)) ==
               "h.5(/companies,v.45(/users,/employees))"

      # The left tile sits under no top-and-bottom divider.
      assert Layout.resize_step(layout, a, :down) == layout
    end
  end

  describe "toggle_split/2 and swap/3" do
    test "toggle flips the split holding the tile" do
      {layout, a} = open!(Layout.empty(), "/companies")
      {layout, b} = open!(layout, "/users", at: a)

      assert Layout.encode(Layout.toggle_split(layout, b)) == "v.5(/companies,/users)"
      assert Layout.toggle_split(layout, "nope") == layout
    end

    test "swap exchanges two tiles' places and keeps their ids" do
      {layout, a} = open!(Layout.empty(), "/companies")
      {layout, b} = open!(layout, "/users", at: a)

      swapped = Layout.swap(layout, a, b)

      assert Layout.encode(swapped) == "h.5(/users,/companies)"
      assert rect(swapped, b) == %{x: 0.0, y: 0.0, w: 0.5, h: 1.0}
      assert Layout.swap(layout, a, "nope") == layout
    end
  end

  describe "neighbor/3 and move/3" do
    setup do
      {layout, a} = open!(Layout.empty(), "/companies")
      {layout, b} = open!(layout, "/users", at: a)
      {layout, c} = open!(layout, "/employees", at: b)
      %{layout: layout, a: a, b: b, c: c}
    end

    test "finds the tile sharing the longest edge", %{layout: layout, a: a, b: b, c: c} do
      assert Layout.neighbor(layout, a, :right) in [b, c]
      assert Layout.neighbor(layout, b, :left) == a
      assert Layout.neighbor(layout, b, :down) == c
      assert Layout.neighbor(layout, c, :up) == b
      assert Layout.neighbor(layout, a, :left) == nil
      assert Layout.neighbor(layout, c, :down) == nil
    end

    test "move swaps with the neighbour and stops at the edge", %{layout: layout, b: b, c: c} do
      assert Layout.encode(Layout.move(layout, c, :up)) ==
               "h.5(/companies,v.5(/employees,/users))"

      assert Layout.move(layout, b, :right) == layout
    end
  end

  describe "encode/1 and decode/1" do
    test "round-trips a nested tree with encoded paths" do
      {layout, a} = open!(Layout.empty(), "/companies?q=a,b&page=2")
      {layout, b} = open!(layout, "/users", at: a)
      {layout, _} = open!(layout, "/employees/(new)", at: b)
      [{outer, _}, _] = Layout.rects(layout).handles
      layout = Layout.resize(layout, outer.id, 0.625)

      encoded = Layout.encode(layout)

      assert encoded == "h.625(/companies?q=a%2Cb&page=2,v.5(/users,/employees/%28new%29))"
      assert {:ok, decoded} = Layout.decode(encoded)
      assert paths(decoded) == ["/companies?q=a,b&page=2", "/users", "/employees/(new)"]
      assert Layout.encode(decoded) == encoded
    end

    test "the empty workspace is the empty string" do
      assert Layout.encode(Layout.empty()) == ""
      assert Layout.decode("") == {:ok, Layout.empty()}
    end

    test "rejects anything outside the grammar" do
      for bad <- [
            "h.5(/a)",
            "h.5(/a,/b",
            "x.5(/a,/b)",
            "h5(/a,/b)",
            "h.5(a,/b)",
            "/a,/b",
            "h.0(/a,/b)",
            ",",
            "%zz",
            "//evil.example/login",
            "%2F%2Fevil.example%2Flogin",
            "h.5(/a,%2F%2Fevil.example)",
            "https%3A%2F%2Fevil.example%2F",
            "/%5Cevil.example"
          ] do
        assert Layout.decode(bad) == :error, "expected #{inspect(bad)} to be rejected"
      end
    end

    test "rejects more tiles than the cap" do
      seven = Enum.map_join(1..7, ",", &"/p/#{&1}")
      encoded = String.duplicate("h.5(", 6) <> seven <> String.duplicate(")", 6)

      assert Layout.decode(encoded) == :error
    end
  end

  describe "reconcile/2" do
    test "keeps the ids of tiles whose path is unchanged" do
      {current, a} = open!(Layout.empty(), "/companies")
      {current, b} = open!(current, "/users", at: a)

      {:ok, incoming} = Layout.decode("v.5(/users,h.5(/companies,/employees))")
      reconciled = Layout.reconcile(current, incoming)

      assert Enum.map(Layout.leaves(reconciled), & &1.id) == [b, a, "t4"]
      assert Layout.encode(reconciled) == "v.5(/users,h.5(/companies,/employees))"
      assert Layout.empty?(Layout.reconcile(current, Layout.empty()))
    end
  end
end
