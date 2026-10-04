defmodule Bilimbi.Base.DashboardTest do
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Dashboard
  alias Bilimbi.Base.Dashboard.ContributionValidator, as: Validator
  alias Bilimbi.Base.Dashboard.Widget
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  defp entry(owner, items), do: %{descriptor: %{id: owner}, payload: items}

  defp install!(items) do
    ContributionRegistry.put_consumers_for_test!(%{dashboard: items})

    on_exit(&ContributionRegistry.clear_for_test!/0)
  end

  describe "Widget struct validation" do
    test "constructs a valid widget" do
      widget = Widget.new!(%{id: "test", label: "Test", embed: "test.panel"})
      assert widget.id == "test"
      assert widget.label == "Test"
    end

    test "raises on missing id" do
      assert_raise ArgumentError, ~r/widget id is required/, fn ->
        Widget.new!(%{label: "Test", embed: "test.panel"})
      end
    end

    test "raises on empty label" do
      assert_raise ArgumentError, ~r/widget label must not be empty/, fn ->
        Widget.new!(%{id: "test", label: "", embed: "test.panel"})
      end
    end

    test "defaults size to :small" do
      widget = Widget.new!(%{id: "test", label: "Test", embed: "test.panel"})
      assert widget.size == :small
    end

    test "validates size enum" do
      assert_raise ArgumentError, ~r/widget size must be/, fn ->
        Widget.new!(%{id: "test", label: "Test", embed: "test.panel", size: :huge})
      end
    end

    test "defaults order to 0" do
      widget = Widget.new!(%{id: "test", label: "Test", embed: "test.panel"})
      assert widget.order == 0
    end

    test "raises on non-string id" do
      assert_raise ArgumentError, ~r/widget id must be a string/, fn ->
        Widget.new!(%{id: 123, label: "Test", embed: "test.panel"})
      end
    end

    test "raises on non-string label" do
      assert_raise ArgumentError, ~r/widget label must be a string/, fn ->
        Widget.new!(%{id: "test", label: :test, embed: "test.panel"})
      end
    end

    test "requires the embed key of the panel that renders it" do
      assert_raise ArgumentError, ~r/widget embed must name the panel/, fn ->
        Widget.new!(%{id: "test", label: "Test"})
      end

      assert_raise ArgumentError, ~r/widget embed must name the panel/, fn ->
        Widget.new!(%{id: "test", label: "Test", embed: ""})
      end
    end

    test "defaults placement to :grid and accepts :section" do
      assert Widget.new!(%{id: "test", label: "Test", embed: "test.panel"}).placement == :grid

      assert Widget.new!(%{id: "test", label: "Test", embed: "test.panel", placement: :section}).placement ==
               :section

      assert_raise ArgumentError, ~r/widget placement must be :grid or :section/, fn ->
        Widget.new!(%{id: "test", label: "Test", embed: "test.panel", placement: :sidebar})
      end
    end

    test "defaults refresh_interval to 0 and rejects a negative one" do
      assert Widget.new!(%{id: "test", label: "Test", embed: "test.panel"}).refresh_interval == 0

      assert_raise ArgumentError,
                   ~r/widget refresh_interval must be a non-negative integer/,
                   fn ->
                     Widget.new!(%{
                       id: "test",
                       label: "Test",
                       embed: "test.panel",
                       refresh_interval: -1
                     })
                   end
    end

    test "rejects a capability that is not a string" do
      assert_raise ArgumentError, ~r/widget capability must be a string or nil/, fn ->
        Widget.new!(%{id: "test", label: "Test", embed: "test.panel", capability: :admin})
      end
    end

    test "raises on negative order" do
      assert_raise ArgumentError, ~r/widget order must be a non-negative integer/, fn ->
        Widget.new!(%{id: "test", label: "Test", embed: "test.panel", order: -1})
      end
    end
  end

  describe "contribution validation" do
    test "orders deterministically by order then id" do
      [%{id: "widget-a"}, %{id: "widget-b"}] =
        Validator.validate_contributions!([
          entry("core/a", [
            %{id: "widget-b", label: "B", embed: "test.panel", order: 20},
            %{id: "widget-a", label: "A", embed: "test.panel", order: 10}
          ])
        ])
    end

    test "same order sorts by id" do
      [%{id: "widget-a"}, %{id: "widget-z"}] =
        Validator.validate_contributions!([
          entry("core/a", [
            %{id: "widget-z", label: "Z", embed: "test.panel", order: 10},
            %{id: "widget-a", label: "A", embed: "test.panel", order: 10}
          ])
        ])
    end

    test "raises on duplicate ids and names both contributors" do
      assert_raise ArgumentError, ~r/duplicate widget ids.*core\/a.*core\/b/s, fn ->
        Validator.validate_contributions!([
          entry("core/a", [%{id: "dup", label: "A", embed: "test.panel"}]),
          entry("core/b", [%{id: "dup", label: "B", embed: "test.panel"}])
        ])
      end
    end

    test "raises when payload is not a list" do
      assert_raise ArgumentError, ~r/dashboard contribution.*must be a list/, fn ->
        Validator.validate_contributions!([entry("core/a", "not-a-list")])
      end
    end
  end

  describe "public API" do
    test "widgets/0 returns validated widgets" do
      install!([
        Widget.new!(%{id: "widget-a", label: "A", embed: "test.panel"})
      ])

      assert [%Widget{id: "widget-a"}] = Dashboard.widgets()
    end

    test "fetch_widget/1 finds a widget by id" do
      install!([
        Widget.new!(%{id: "widget-a", label: "A", embed: "test.panel"})
      ])

      assert {:ok, %Widget{id: "widget-a"}} = Dashboard.fetch_widget("widget-a")
      assert :error = Dashboard.fetch_widget("missing")
    end

    test "widgets/0 and sections/0 split the catalogue by placement" do
      install!([
        Widget.new!(%{id: "widget-a", label: "A", embed: "test.panel"}),
        Widget.new!(%{id: "section-a", label: "S", embed: "test.section", placement: :section})
      ])

      assert [%Widget{id: "widget-a"}, %Widget{id: "section-a"}] = Dashboard.entries()
      assert [%Widget{id: "widget-a"}] = Dashboard.widgets()
      assert [%Widget{id: "section-a"}] = Dashboard.sections()
      assert :error = Dashboard.fetch_widget("section-a")
    end
  end
end
