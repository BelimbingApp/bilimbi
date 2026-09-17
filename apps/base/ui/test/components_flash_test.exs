defmodule Bilimbi.Base.UI.ComponentsFlashTest do
  @moduledoc """
  Tests for `<.flash>`: one message per severity, with the ARIA role and the
  visual role its severity implies. The look is asserted through what a
  reader perceives — the role announced and the icon shown — not through
  colour class strings, so a restyle does not break these.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  alias Bilimbi.Base.UI.IconRegistry

  @kinds [:success, :info, :warning, :error]

  defp render_flash(kind, flash) do
    render_component(
      fn assigns ->
        ~H"""
        <.flash kind={@kind} flash={@flash} />
        """
      end,
      %{kind: kind, flash: flash}
    )
  end

  # The opening tag of the message element, where its role and bindings live.
  defp message_tag(html, kind) do
    case Regex.run(~r/<div[^>]*\sid="flash-#{kind}"[^>]*>/, html) do
      [tag] -> tag
      nil -> nil
    end
  end

  defp role(kind) do
    tag = message_tag(render_flash(kind, %{Atom.to_string(kind) => "message"}), kind)
    [_, role] = Regex.run(~r/\srole="([a-z]+)"/, tag)
    role
  end

  defp icon_name(kind) do
    html = render_flash(kind, %{Atom.to_string(kind) => "message"})
    [_, name] = Regex.run(~r/class="(hero-[a-z0-9-]+) size-5 shrink-0"/, html)
    name
  end

  test "every severity is announced as an alert" do
    for kind <- @kinds, do: assert(role(kind) == "alert")
  end

  test "each severity renders only its own message" do
    for kind <- @kinds do
      html = render_flash(kind, %{Atom.to_string(kind) => "#{kind} message"})
      assert message_tag(html, kind)
      assert html =~ "#{kind} message"
    end

    html = render_flash(:info, %{"success" => "saved"})
    refute message_tag(html, :info)
    refute html =~ "saved"
  end

  test "success and info are told apart by their icons" do
    {:hero, information} = IconRegistry.lookup("information")
    {:hero, success} = IconRegistry.lookup("success")

    assert icon_name(:info) == information
    assert icon_name(:success) == success
    refute icon_name(:info) == icon_name(:success)
  end

  test "a message never carries a dismissal timer of its own" do
    for kind <- @kinds do
      html = render_flash(kind, %{Atom.to_string(kind) => "message"})
      refute message_tag(html, kind) =~ "phx-hook"
    end
  end
end
