defmodule Bilimbi.Base.UI.LayoutsFlashGroupTest do
  @moduledoc """
  Tests for `Layouts.flash_group/1`, the one production outlet for flash
  messages: the group is the one positioned stack, so messages sit in a
  column instead of covering each other, and only `:success` carries the
  dismissal timer.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.UI.Layouts

  @all %{
    "error" => "The record could not be saved.",
    "warning" => "Review the missing address.",
    "success" => "Saved.",
    "info" => "Future records only."
  }

  defp render_group(flash) do
    render_component(
      fn assigns ->
        ~H"""
        <Layouts.flash_group flash={@flash} />
        """
      end,
      %{flash: flash}
    )
  end

  # The opening tag of the element with this id, where its role and bindings live.
  defp tag(html, id) do
    case Regex.run(~r/<div[^>]*\sid="#{id}"[^>]*>/, html) do
      [tag] -> tag
      nil -> nil
    end
  end

  defp timed?(html, id), do: tag(html, id) =~ ~s(phx-hook="FlashAutoDismiss")

  # Where the element with this id starts in the rendered document.
  defp position(html, id) do
    [{start, _length}] = Regex.run(~r/<div[^>]*\sid="#{id}"[^>]*>/, html, return: :index)
    start
  end

  test "the group is the one positioned stack, so no message covers another" do
    html = render_group(@all)

    group = tag(html, "flash-group")
    assert group =~ ~r/\bfixed\b/, "the group does not position the stack"
    assert group =~ ~r/\bflex-col\b/, "the group does not lay its messages out in a column"

    for {kind, text} <- @all do
      message = tag(html, "flash-#{kind}")
      assert message, "no #{kind} message rendered"
      assert html =~ text

      refute message =~ ~r/\bfixed\b/,
             "the #{kind} message claims a slot of its own instead of stacking in the group"
    end

    severity_order = Enum.map(~w(error warning success info), &position(html, "flash-#{&1}"))
    assert severity_order == Enum.sort(severity_order), "messages do not stack most severe first"
  end

  test "success dismisses on a timer; info, warning and error stay until dismissed" do
    html = render_group(@all)

    assert timed?(html, "flash-success")
    refute timed?(html, "flash-info")
    refute timed?(html, "flash-warning")
    refute timed?(html, "flash-error")
  end

  test "the reconnect notices are errors and never carry a timer" do
    html = render_group(%{})

    for id <- ["client-error", "server-error"] do
      assert tag(html, id) =~ ~s(role="alert")
      refute timed?(html, id)
    end
  end

  test "the group is a live region so an inserted message is announced" do
    html = render_group(%{"info" => "Saved."})

    assert tag(html, "flash-group") =~ ~s(aria-live="polite")
  end
end
