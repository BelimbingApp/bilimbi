defmodule Bilimbi.Base.DashboardTest do
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Dashboard
  alias Bilimbi.Base.Dashboard.ContributionValidator, as: Validator
  alias Bilimbi.Base.Dashboard.Widget
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  defp entry(owner, items), do: %{descriptor: %{id: owner}, payload: items}

  defp install!(items) do
    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "test",
      consumers: %{dashboard: items}
    })

    on_exit(&ContributionRegistry.clear_for_test!/0)
  end

  describe "Widget struct validation" do
    test "constructs a valid widget" do
      widget = Widget.new!(%{id: "test", label: "Test"})
      assert widget.id == "test"
      assert widget.label == "Test"
    end

    test "raises on missing id" do
      assert_raise ArgumentError, ~r/widget id is required/, fn ->
        Widget.new!(%{label: "Test"})
      end
    end

    test "raises on empty label" do
      assert_raise ArgumentError, ~r/widget label must not be empty/, fn ->
        Widget.new!(%{id: "test", label: ""})
      end
    end

    test "defaults size to :small" do
      widget = Widget.new!(%{id: "test", label: "Test"})
      assert widget.size == :small
    end

    test "validates size enum" do
      assert_raise ArgumentError, ~r/widget size must be/, fn ->
        Widget.new!(%{id: "test", label: "Test", size: :huge})
      end
    end

    test "defaults order to 0" do
      widget = Widget.new!(%{id: "test", label: "Test"})
      assert widget.order == 0
    end

    test "raises on non-string id" do
      assert_raise ArgumentError, ~r/widget id must be a string/, fn ->
        Widget.new!(%{id: 123, label: "Test"})
      end
    end

    test "raises on non-string label" do
      assert_raise ArgumentError, ~r/widget label must be a string/, fn ->
        Widget.new!(%{id: "test", label: :test})
      end
    end

    test "raises on negative order" do
      assert_raise ArgumentError, ~r/widget order must be a non-negative integer/, fn ->
        Widget.new!(%{id: "test", label: "Test", order: -1})
      end
    end
  end

  defmodule DummyWidgetModule do
    @behaviour Bilimbi.Base.Dashboard.Widget

    @impl true
    def widget_title, do: "Dummy"

    @impl true
    def widget_size, do: :medium

    @impl true
    def widget_refresh_interval, do: 60_000

    @impl true
    def widget_assigns, do: [:dummy_count]
  end

  describe "Widget behaviour" do
    test "implements callbacks properly" do
      assert DummyWidgetModule.widget_title() == "Dummy"
      assert DummyWidgetModule.widget_size() == :medium
      assert DummyWidgetModule.widget_refresh_interval() == 60_000
      assert DummyWidgetModule.widget_assigns() == [:dummy_count]
    end
  end

  describe "contribution validation" do
    test "orders deterministically by order then id" do
      [%{id: "widget-a"}, %{id: "widget-b"}] =
        Validator.validate_contributions!([
          entry("core/a", [
            %{id: "widget-b", label: "B", order: 20},
            %{id: "widget-a", label: "A", order: 10}
          ])
        ])
    end

    test "same order sorts by id" do
      [%{id: "widget-a"}, %{id: "widget-z"}] =
        Validator.validate_contributions!([
          entry("core/a", [
            %{id: "widget-z", label: "Z", order: 10},
            %{id: "widget-a", label: "A", order: 10}
          ])
        ])
    end

    test "raises on duplicate ids and names both contributors" do
      assert_raise ArgumentError, ~r/duplicate widget ids.*core\/a.*core\/b/s, fn ->
        Validator.validate_contributions!([
          entry("core/a", [%{id: "dup", label: "A"}]),
          entry("core/b", [%{id: "dup", label: "B"}])
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
        Widget.new!(%{id: "widget-a", label: "A"})
      ])

      assert [%Widget{id: "widget-a"}] = Dashboard.widgets()
    end

    test "fetch_widget/1 finds a widget by id" do
      install!([
        Widget.new!(%{id: "widget-a", label: "A"})
      ])

      assert {:ok, %Widget{id: "widget-a"}} = Dashboard.fetch_widget("widget-a")
      assert :error = Dashboard.fetch_widget("missing")
    end
  end
end
