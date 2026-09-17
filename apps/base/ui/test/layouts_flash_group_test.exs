defmodule Bilimbi.Base.UI.LayoutsFlashGroupTest do
  @moduledoc """
  Tests for `Layouts.flash_group/1`, the one production outlet for flash
  messages: every severity present at once is readable, and only a completed
  write confirms itself away on a timer.
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

  test "several messages are all present instead of one replacing another" do
    html = render_group(@all)

    for {kind, text} <- @all do
      assert tag(html, "flash-#{kind}"), "no #{kind} message rendered"
      assert html =~ text
    end
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
