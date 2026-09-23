defmodule Bilimbi.Base.UI.ComponentsAlertTest do
  @moduledoc """
  Tests for `<.alert>`, the inline counterpart of Belimbing's `x-ui.alert`:
  each kind is announced by what it does and no two kinds look alike. The
  look is asserted through the role announced, the icon shown and the
  distinctness of the colouring — not through colour class strings, so a
  restyle does not break these.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  alias Bilimbi.Base.UI.IconRegistry

  @kinds [:info, :success, :warning, :error]

  defp render_alert(kind) do
    render_component(
      fn assigns ->
        ~H"""
        <.alert id="alert" kind={@kind}>message</.alert>
        """
      end,
      %{kind: kind}
    )
  end

  # The opening tag of the alert, where its role and colouring live.
  defp alert_tag(html) do
    [tag] = Regex.run(~r/<div[^>]*\sid="alert"[^>]*>/, html)
    tag
  end

  defp attribute(tag, name) do
    [_, value] = Regex.run(~r/\s#{name}="([^"]+)"/, tag)
    value
  end

  defp icon_name(html) do
    [_, name] = Regex.run(~r/class="(hero-[a-z0-9-]+) mt-0.5 size-4 shrink-0"/, html)
    name
  end

  test "success and info are a polite status; warning and error an assertive alert" do
    for kind <- [:success, :info] do
      tag = alert_tag(render_alert(kind))
      assert attribute(tag, "role") == "status"
      assert attribute(tag, "aria-live") == "polite"
    end

    for kind <- [:warning, :error] do
      tag = alert_tag(render_alert(kind))
      assert attribute(tag, "role") == "alert"
      assert attribute(tag, "aria-live") == "assertive"
    end
  end

  test "each kind shows its own status icon, the same glyphs the flash uses" do
    for kind <- @kinds do
      icon = if kind == :info, do: "information", else: Atom.to_string(kind)
      {:hero, expected} = IconRegistry.lookup(icon)
      assert icon_name(render_alert(kind)) == expected
    end
  end

  test "no two kinds share one colouring" do
    surfaces = Enum.map(@kinds, &attribute(alert_tag(render_alert(&1)), "class"))
    assert Enum.uniq(surfaces) == surfaces
  end
end
