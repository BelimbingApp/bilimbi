defmodule Bilimbi.Base.UI.ComponentsInlineEditTest do
  @moduledoc """
  Tests for the shared <.inline_edit> component.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  test "renders display element with pencil icon and hook attributes" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.inline_edit
        id="country-42-name"
        value="Malaysia"
        id_value={42}
        save_event="save-country-name"
        name="country"
        label="Edit country name"
      />
      """)

    assert html =~ ~s(id="country-42-name")
    assert html =~ ~s(phx-hook="InlineEdit")
    assert html =~ ~s(data-id="42")
    assert html =~ ~s(data-field="country")
    assert html =~ ~s(data-save-event="save-country-name")
    assert html =~ ~s(data-role="trigger")
    assert html =~ "Malaysia"
    assert html =~ ~s(data-role="input")
    assert html =~ ~s(name="country")
    assert html =~ ~s(value="Malaysia")
    assert html =~ "hero-pencil"
  end
end
