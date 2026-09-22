defmodule Bilimbi.Base.UI.ComponentsCardTest do
  @moduledoc """
  The card is the panel frame every screen reuses. A card that drops its
  inner padding sits flush against its content — the list-page shape holding
  nothing but a table and its pager — so the frame must not round corners the
  content reaches. These lock that decision in the one component that makes
  it, rather than in the 26 screens that would otherwise each pass a class.
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

  test "a padded card keeps its padding and its radius" do
    html = render_component(&preview/1, %{})

    assert html =~ "rounded-xl border border-line bg-surface shadow-xs"
    assert inner_classes(html) == ["p-2"]
  end

  test "the p-0 signal drops the radius" do
    html = render_component(&preview/1, %{inner_class: "p-0"})

    refute html =~ "rounded"
    assert html =~ "border border-line bg-surface shadow-xs"
  end

  test "the corner is the only geometry the signal changes" do
    padded = render_component(&preview/1, %{})
    flat = render_component(&preview/1, %{inner_class: "p-0"})

    assert inner_classes(padded) == ["p-2"]
    assert inner_classes(flat) == ["p-2", "p-0"]

    assert String.replace(padded, "rounded-xl ", "") ==
             String.replace(flat, "p-2 p-0", "p-2 ")
  end

  test "a card that chooses different padding keeps its radius" do
    html = render_component(&preview/1, %{inner_class: "p-5 sm:p-6 space-y-4"})

    assert html =~ "rounded-xl"
    assert inner_classes(html) == ["p-2", "p-5", "sm:p-6", "space-y-4"]
  end

  test "a titled card flattens as a whole, so the frame has one geometry" do
    titled = render_component(&preview/1, %{title: "Recent regressions", inner_class: "p-0"})

    assert titled =~ "Recent regressions"
    refute titled =~ "rounded"
  end
end
