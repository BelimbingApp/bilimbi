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
      <.action_link
        id="company-departments-manage"
        icon="manage"
        navigate="/companies/7/departments"
        title="Manage departments"
      >
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

  test "names its destination to assistive technology, not only to the mouse" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.action_link
        id="companies-department-types"
        icon="manage"
        navigate="/companies/department-types"
        title="Manage department types"
      >
        Department Types
      </.action_link>
      """)

    assert html =~ ~s(href="/companies/department-types")
    assert html =~ "hero-cog-6-tooth"
    assert attribute(html, "title") == "Manage department types"
    assert attribute(html, "aria-label") == attribute(html, "title")
    assert visible_text(html) == "Department Types"
  end

  test "shares the back link's treatment so the two cannot drift apart" do
    assigns = %{}

    action =
      rendered_to_string(~H"""
      <.action_link id="a" icon="manage" navigate="/x" title="Manage x">Manage</.action_link>
      """)

    back =
      rendered_to_string(~H"""
      <.back_link id="b" navigate="/x" />
      """)

    assert class_of(action) == class_of(back)
  end

  defp class_of(html), do: attribute(html, "class")

  defp attribute(html, name) do
    [_, value] = Regex.run(~r/\b#{name}="([^"]*)"/, html)
    value
  end

  defp visible_text(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
