defmodule Bilimbi.Base.UI.ComponentsActionLinkTest do
  @moduledoc """
  The demoted secondary action a section renders as a link instead of a button.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  test "renders a plain navigation link carrying the registry glyph, never a button" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.action_link id="company-departments-manage" icon="manage" navigate="/companies/7/departments">
        Manage
      </.action_link>
      """)

    assert html =~ ~r/<a\b[^>]*\bid="company-departments-manage"/
    assert html =~ ~s(href="/companies/7/departments")
    assert html =~ ~s(data-phx-link="redirect")
    assert html =~ "hero-cog-6-tooth"
    assert visible_text(html) == "Manage"
    refute html =~ "<button"
    refute html =~ "bg-action"
    refute html =~ "border"
    assert html =~ "text-link"
  end

  test "carries no glyph when the action has none, and names itself through title" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.action_link id="employee-types" navigate="/employee-types" title="Manage employee types">
        Employee types
      </.action_link>
      """)

    refute html =~ "<svg"
    refute html =~ "hero-"
    assert html =~ ~s(title="Manage employee types")
    assert visible_text(html) == "Employee types"
  end

  test "shares the back link's treatment so the two cannot drift apart" do
    assigns = %{}

    action =
      rendered_to_string(~H"""
      <.action_link id="a" navigate="/x">Manage</.action_link>
      """)

    back =
      rendered_to_string(~H"""
      <.back_link id="b" navigate="/x" />
      """)

    assert class_of(action) == class_of(back)
  end

  defp class_of(html) do
    [_, class] = Regex.run(~r/class="([^"]*)"/, html)
    class
  end

  defp visible_text(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
