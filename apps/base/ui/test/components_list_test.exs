defmodule Bilimbi.Base.UI.ComponentsListTest do
  @moduledoc """
  The facts list is the one shape a detail page's facts take. A page that
  rebuilds `<dl>` by hand drifts from it, so these lock the primitive: a row
  per fact with the label in its own column, a left-aligned value cell that
  can name itself, and enough room in that cell for an in-place editor.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  test "renders one definition row per fact with the label beside the value" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.list>
        <:item title="Company">Acme Holdings</:item>
        <:item title="Status">
          <.badge kind={:success}>Active</.badge>
        </:item>
      </.list>
      """)

    assert html =~ "<dl"
    assert html =~ ~r/<dt[^>]*>\s*Company\s*<\/dt>/
    assert html =~ ~r/<dd[^>]*>\s*Acme Holdings\s*<\/dd>/
    assert html =~ ~r/<dt[^>]*>\s*Status\s*<\/dt>/
    assert html =~ "Active"

    # Label column beside a value column from `sm` up, stacked below it.
    assert html =~ "sm:grid-cols-[10rem_minmax(0,1fr)]"
    assert html =~ "grid-cols-1"
  end

  test "the value cell is left-aligned and takes the row's width" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.list>
        <:item title="Label">Head Office</:item>
      </.list>
      """)

    [_, dd_tag] = String.split(html, "<dd", parts: 2)
    [dd_tag, _] = String.split(dd_tag, ">", parts: 2)

    refute dd_tag =~ "text-right"
    assert dd_tag =~ "min-w-0"
  end

  test "the list carries its id only when the caller names one" do
    assigns = %{}

    named =
      rendered_to_string(~H"""
      <.list id="facts">
        <:item title="Name">Acme Holdings</:item>
      </.list>
      """)

    unnamed =
      rendered_to_string(~H"""
      <.list>
        <:item title="Name">Acme Holdings</:item>
      </.list>
      """)

    assert named =~ ~r/<dl[^>]*\sid="facts"/
    refute unnamed =~ ~r/<dl[^>]*\sid=/
  end

  test "an item id names the value cell, not the row" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.list>
        <:item title="Label" id="address-view-label">Head Office</:item>
        <:item title="Phone">+60 3</:item>
      </.list>
      """)

    assert html =~ ~r/<dd\b[^>]*\bid="address-view-label"[^>]*>\s*Head Office/
    refute html =~ ~r/<div\b[^>]*\bid="address-view-label"/
    refute html =~ ~r/<dt\b[^>]*\bid="address-view-label"/
    # An item without an id renders no empty id attribute.
    refute html =~ ~s(id="")
  end

  test "hosts an in-place editor and its commit status inside the value cell" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.list>
        <:item title="Label" id="address-view-label">
          <.inline_edit
            id="address-label"
            value="Head Office"
            name="label"
            label="Label"
            allow_empty
            status={:saved}
            save_event="save_field"
          />
        </:item>
      </.list>
      """)

    [_, cell] = String.split(html, ~s(id="address-view-label"), parts: 2)
    [cell, _] = String.split(cell, "</dd>", parts: 2)

    assert cell =~ ~s(phx-hook="InlineEdit")
    assert cell =~ ~s(data-save-event="save_field")
    assert cell =~ ~s(id="address-label-status")
    assert cell =~ ~s(role="status")
    assert cell =~ "Saved"
  end
end
