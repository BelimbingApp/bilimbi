defmodule Bilimbi.Base.UI.ComponentsPanelNoticeTest do
  @moduledoc """
  Tests for `<.panel_notice>`: the one owner of how a panel's outcome reads.
  The look is asserted through what a reader perceives — the role announced,
  the kind the element carries and the icon shown — not through colour class
  strings, so a restyle does not break these. A completed write is told
  apart from a plain statement the same way the page-level flash tells them
  apart: by kind and icon.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  alias Bilimbi.Base.UI.IconRegistry
  alias Phoenix.LiveView.JS

  @kinds [:info, :success, :error]

  defp render_notice(kind, message \\ "message") do
    render_component(
      fn assigns ->
        ~H"""
        <.panel_notice id="panel-notice" kind={@kind} on_dismiss={JS.push("clear_notice")}>
          {@message}
        </.panel_notice>
        """
      end,
      %{kind: kind, message: message}
    )
  end

  # The opening tag of the notice, where its role and kind live.
  defp notice_tag(html) do
    [tag] = Regex.run(~r/<div[^>]*\sid="panel-notice"[^>]*>/, html)
    tag
  end

  defp attribute(tag, name) do
    [_, value] = Regex.run(~r/\s#{name}="([^"]+)"/, tag)
    value
  end

  defp surface_classes(kind), do: attribute(notice_tag(render_notice(kind)), "class")

  defp icon_name(html) do
    [_, name] = Regex.run(~r/class="(hero-[a-z0-9-]+) mt-0.5 size-4 shrink-0"/, html)
    name
  end

  test "a completed write renders the success kind and is announced politely" do
    tag = notice_tag(render_notice(:success, "Address attached."))

    assert attribute(tag, "data-kind") == "success"
    assert attribute(tag, "role") == "status"
    assert attribute(tag, "aria-live") == "polite"
  end

  test "an informational notice renders the info kind and is announced politely" do
    tag = notice_tag(render_notice(:info))

    assert attribute(tag, "data-kind") == "info"
    assert attribute(tag, "role") == "status"
    assert attribute(tag, "aria-live") == "polite"
  end

  test "an error renders the error kind and interrupts as an alert" do
    tag = notice_tag(render_notice(:error, "Failed to attach address."))

    assert attribute(tag, "data-kind") == "error"
    assert attribute(tag, "role") == "alert"
    assert attribute(tag, "aria-live") == "assertive"
  end

  test "no two kinds share one colouring" do
    surfaces = Enum.map(@kinds, &surface_classes/1)
    assert Enum.uniq(surfaces) == surfaces
  end

  test "each kind shows its own status icon, the same glyphs the flash uses" do
    for kind <- @kinds do
      icon = if kind == :info, do: "information", else: Atom.to_string(kind)
      {:hero, expected} = IconRegistry.lookup(icon)
      assert icon_name(render_notice(kind)) == expected
    end
  end

  test "the message renders with a labelled Dismiss control that runs the caller's command" do
    html = render_notice(:success, "Address unlinked.")

    assert html =~ "Address unlinked."
    assert html =~ ~s(id="panel-notice-dismiss")
    assert html =~ ~s(aria-label="Dismiss notice")
    assert html =~ "clear_notice"
  end
end
