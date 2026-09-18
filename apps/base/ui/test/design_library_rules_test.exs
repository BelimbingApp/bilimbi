defmodule Bilimbi.Base.UI.DesignLibraryRulesTest do
  @moduledoc """
  Exercises the Design Library drift rules on fixtures rather than on the
  library itself.

  `Bilimbi.Base.UI.DesignLibraryImitationTest` reports what today's template
  does wrong, so it cannot also show that the rules still catch the next
  imitation: a rule that silently stopped matching would leave that suite red
  for the reasons it is already red. These fixtures close that gap. Each one
  is a minimal components area, and each assertion says which specimens the
  rules must reject and which they must leave alone.

  This module is deliberately not tagged `:design_library_drift`; it runs on
  every `mix test` and must stay green.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.DesignLibrarySource, as: Source

  describe "the anchor rule" do
    test "accepts a grouping section the sidebar menu links to" do
      assert Source.anchor_problems(area("")) == []
    end

    test "rejects an imitation rewritten as a section with a component-* id" do
      nodes =
        area("""
        <section id="component-page" class="space-y-3">
          <div class="h-2 w-full rounded-full bg-brand-strong"></div>
          <div class="mx-auto h-2 w-1/2 rounded-full bg-brand-strong"></div>
        </section>
        """)

      assert [problem] = Source.anchor_problems(nodes)
      assert problem =~ "#component-page"
      assert problem =~ "never calls it"
    end

    test "rejects a block that claims a component the product has not built" do
      nodes =
        area("""
        <.card id="component-stepper" title="Stepper">
          <div class="flex gap-2">
            <div class="size-6 rounded-full bg-brand-strong"></div>
            <div class="size-6 rounded-full bg-surface-muted"></div>
          </div>
        </.card>
        """)

      assert [problem] = Source.anchor_problems(nodes)
      assert problem =~ "#component-stepper"
      assert problem =~ "not a public component"
    end

    test "accepts a block that calls the component its anchor names" do
      nodes =
        area("""
        <.card id="component-badge" title="Badge">
          <.badge kind={:success}>Active</.badge>
        </.card>
        """)

      assert Source.anchor_problems(nodes) == []
    end
  end

  describe "the control-markup rule" do
    test "leaves the sidebar menu's own nav and links alone" do
      assert Source.control_problems(area("")) == []
    end

    test "rejects tabs hand-built from a nav and links" do
      nodes =
        area("""
        <.card id="component-badge" title="Tabs">
          <.badge>Active</.badge>
          <nav class="flex gap-1 border-b border-line">
            <a href="#overview" class="px-3 py-2">Overview</a>
          </nav>
        </.card>
        """)

      problems = Source.control_problems(nodes)

      assert Enum.any?(problems, &(&1 =~ "<nav>"))
      assert Enum.any?(problems, &(&1 =~ "<a>"))
    end

    test "rejects a control built from styled divs carrying interaction state" do
      nodes =
        area("""
        <.card id="component-badge" title="Tabs">
          <.badge>Active</.badge>
          <div class="flex gap-1">
            <div role="tab" aria-selected="true" class="px-3 py-2">Overview</div>
          </div>
        </.card>
        """)

      assert [problem] = Source.control_problems(nodes)
      assert problem =~ "<div>"
      assert problem =~ "role"
    end

    test "reports one reason per element" do
      nodes =
        area("""
        <.card id="component-badge" title="Tabs">
          <.badge>Active</.badge>
          <a href="#overview" role="tab" aria-selected="true" class="px-3 py-2">Overview</a>
        </.card>
        """)

      assert [_single] = Source.control_problems(nodes)
    end
  end

  describe "the catalog" do
    test "a heading-anchored entry does not present a component through blocks that frame others" do
      nodes =
        area("""
        <h2 id="component-card">Cards</h2>
        <.card id="component-badge" title="Badge">
          <.badge kind={:success}>Active</.badge>
        </.card>
        """)

      assert Source.entry_calls(:card, Source.catalog(nodes)) == []
      assert [problem] = Source.anchor_problems(nodes)
      assert problem =~ "#component-card"
      assert problem =~ "never calls it"
    end

    test "a heading-anchored entry does not present a component through blocks that frame imitations" do
      nodes =
        area("""
        <h2 id="component-card">Cards</h2>
        <.card id="component-navigation" title="Navigation">
          <div class="px-2 py-1">Companies</div>
        </.card>
        """)

      assert Source.entry_calls(:card, Source.catalog(nodes)) == []
    end

    test "a heading-anchored entry presents a component through a block that frames nothing else" do
      nodes =
        area("""
        <h2 id="component-card">Cards</h2>
        <.card title="A plain card">Body</.card>
        """)

      assert [_call] = Source.entry_calls(:card, Source.catalog(nodes))
      assert Source.anchor_problems(nodes) == []
    end
  end

  describe "the specimen rule" do
    test "rejects an id-less card the library never names" do
      nodes = area(~S|<.card title="Brand new specimen"><p>Bars</p></.card>|)

      assert Enum.any?(Source.specimen_problems(nodes), &(&1 =~ "Brand new specimen"))
    end

    test "accepts an id-less card the library declares" do
      nodes = area(~S|<.card title="Choice controls"><p>Bars</p></.card>|)

      refute Enum.any?(Source.specimen_problems(nodes), &(&1 =~ "Choice controls"))
    end

    test "accepts a card that sits inside an anchored block" do
      nodes =
        area("""
        <.card id="component-badge" title="Badge">
          <.card title="Brand new specimen"><.badge>Active</.badge></.card>
        </.card>
        """)

      refute Enum.any?(Source.specimen_problems(nodes), &(&1 =~ "Brand new specimen"))
    end

    test "reports a declaration that matches no card" do
      problems = Source.specimen_problems(area(""))

      assert Enum.any?(problems, &(&1 =~ "Connection interrupted" and &1 =~ "matches no"))
    end
  end

  describe "reading the template" do
    test "counts a self-closing slot as present" do
      [call] =
        area(~S|<.list><:item title="Company" /></.list>|)
        |> Source.presented()
        |> Enum.filter(&(&1.kind == :component and &1.name == "list"))

      assert [slot] = Source.slots(call, "item")
      assert Source.attr(slot, "title") == {:literal, "Company"}
      refute Source.inner_block?(call)
    end

    test "walks a template that carries a HEEx comment" do
      nodes = area(~S|<%!-- Structure --%><.badge>Active</.badge>|)

      assert Enum.any?(Source.presented(nodes), &(&1.name == "badge"))
    end
  end

  # A minimal components area: the sidebar menu the grouping-section exemption
  # is anchored to, the content wrapper, and one menu-linked grouping section
  # holding the specimen under test.
  defp area(specimen) do
    Source.parse("""
    <%= if @area == :components do %>
      <section id="components">
        <aside id="component-secondary-menu">
          <nav aria-label="Component sections">
            <a href="#component-structure">Structure</a>
          </nav>
        </aside>
        <div id="component-content">
          <section id="component-structure">
            #{specimen}
          </section>
        </div>
      </section>
    <% end %>
    """)
  end
end
