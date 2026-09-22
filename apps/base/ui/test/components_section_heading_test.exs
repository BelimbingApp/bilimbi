defmodule Bilimbi.Base.UI.ComponentsSectionHeadingTest do
  @moduledoc """
  The heading row every section of a detail page opens with. Pages used to
  write it by hand in four spellings; these lock the one shape so the next
  section reaches for the component rather than a class string.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  test "renders the title as a level-two heading in the small-caps treatment" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.section_heading id="company-details-heading" title="Company Details" />
      """)

    assert html =~ ~r/<h2\b[^>]*\bid="company-details-heading"[^>]*>\s*Company Details\s*<\/h2>/
    assert html =~ "text-xs font-semibold uppercase tracking-wider text-ink-subtle"
    refute html =~ "<h3"
    # Nothing renders for the slots that were not given.
    refute html =~ "mt-0.5 text-xs text-ink-subtle"
    refute html =~ "shrink-0 items-center gap-2"
  end

  test "a count renders as a badge beside the title" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.section_heading title="Departments" count={3} />
      """)

    [_, after_title] = String.split(html, "</h2>", parts: 2)

    assert html =~ "Departments"
    assert after_title =~ "rounded-full"
    assert after_title =~ ~r/>\s*3\s*<\/span>/
  end

  test "title actions sit beside the title and actions end the row" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.section_heading title="Geographic Location">
        <:title_actions>
          <.icon_button id="edit-location" icon="edit" label="Edit location" context={:inline} />
        </:title_actions>
        <:description>Applied together.</:description>
        <:actions>
          <.action_link
            id="manage"
            icon="manage"
            navigate="/companies/1/departments"
            title="Manage departments"
          >
            Manage
          </.action_link>
        </:actions>
      </.section_heading>
      """)

    [before_description, after_description] = String.split(html, "Applied together.", parts: 2)

    # The title action shares the title's row, before the description.
    assert before_description =~ ~s(id="edit-location")
    assert before_description =~ "Geographic Location"
    # The trailing action comes after the title block, at the end of the row.
    assert after_description =~ ~s(id="manage")
    assert after_description =~ "Manage"
  end
end
