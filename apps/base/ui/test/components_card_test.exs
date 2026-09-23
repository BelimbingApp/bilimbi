defmodule Bilimbi.Base.UI.ComponentsCardTest do
  @moduledoc """
  The card is the panel frame every screen reuses. A card that drops its
  inner padding sits flush against its content — the list-page shape holding
  nothing but a table and its pager — so the frame must not round corners the
  content reaches, and the padding the caller asked to drop must actually be
  gone. Both are decided in the one component that makes them, rather than in
  the 26 screens that would otherwise each pass a class.

  The padding half is decided in Elixir on purpose. Two utilities of equal
  specificity are ranked by their order in the generated stylesheet, where
  `.p-0` precedes `.p-2`, so a card that emitted `p-2 p-0` rendered 8px while
  claiming none. These lock in that the caller's padding is the only padding
  emitted.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  defp preview(assigns) do
    assigns =
      assigns
      |> Map.put_new(:inner_class, nil)
      |> Map.put_new(:title, nil)

    ~H"""
    <.card id="panel" title={@title} inner_class={@inner_class}>
      <p>Body</p>
    </.card>
    """
  end

  defp inner_classes(html) do
    [_, rest] = String.split(html, ~s(<div class="), parts: 2)
    [classes, _] = String.split(rest, ~s("), parts: 2)
    String.split(classes)
  end

  test "a card that states no padding keeps the default and its radius" do
    html = render_component(&preview/1, %{})

    assert html =~ "rounded-xl border border-line bg-surface shadow-xs"
    assert inner_classes(html) == ["p-2"]
  end

  test "the p-0 signal drops the radius" do
    html = render_component(&preview/1, %{inner_class: "p-0"})

    refute html =~ "rounded"
    assert html =~ "border border-line bg-surface shadow-xs"
  end

  test "a caller's padding replaces the default instead of competing with it" do
    assert inner_classes(render_component(&preview/1, %{inner_class: "p-0"})) == ["p-0"]

    assert inner_classes(render_component(&preview/1, %{inner_class: "p-5 sm:p-6 space-y-4"})) ==
             ["p-5", "sm:p-6", "space-y-4"]

    assert inner_classes(render_component(&preview/1, %{inner_class: ["space-y-2", "p-3"]})) ==
             ["space-y-2", "p-3"]
  end

  test "the padding a caller leaves unstated stays at the default" do
    # An axis-only class sets nothing on the other axis, and a responsive
    # shorthand sets nothing below its breakpoint, so the default stays for
    # what they leave alone.
    assert inner_classes(render_component(&preview/1, %{inner_class: "px-4"})) == ["p-2", "px-4"]

    assert inner_classes(render_component(&preview/1, %{inner_class: "px-3 py-2"})) ==
             ["p-2", "px-3", "py-2"]

    assert inner_classes(render_component(&preview/1, %{inner_class: "sm:p-6"})) ==
             ["p-2", "sm:p-6"]

    assert inner_classes(render_component(&preview/1, %{inner_class: [nil, false, "space-y-4"]})) ==
             ["p-2", "space-y-4"]
  end

  test "the corner is the only frame geometry the signal changes" do
    padded = render_component(&preview/1, %{})
    flat = render_component(&preview/1, %{inner_class: "p-0"})

    assert String.replace(padded, "rounded-xl ", "") ==
             String.replace(flat, ~s(class="p-0"), ~s(class="p-2"))
  end

  test "a card that chooses different padding keeps its radius" do
    html = render_component(&preview/1, %{inner_class: "p-5 sm:p-6 space-y-4"})

    assert html =~ "rounded-xl"
  end

  test "a titled card flattens as a whole, so the frame has one geometry" do
    titled = render_component(&preview/1, %{title: "Recent regressions", inner_class: "p-0"})

    assert titled =~ "Recent regressions"
    refute titled =~ "rounded"
  end
end
