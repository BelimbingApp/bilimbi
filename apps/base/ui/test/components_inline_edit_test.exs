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
    refute html =~ "data-allow-empty"
    refute html =~ ~s(data-role="status")
    assert html =~ ~s(data-role="saving")
  end

  test "shows the empty placeholder and opts into empty commits only when told" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.inline_edit id="address-line2" value="" name="line2" label="Address Line 2" allow_empty />
      """)

    assert html =~ ~s(data-allow-empty)
    assert html =~ "—"
    assert html =~ ~s(value="")
  end

  test "reports a saved commit on the field" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.inline_edit id="address-label" value="HQ" name="label" label="Label" status={:saved} />
      """)

    assert html =~ ~s(id="address-label-status")
    assert html =~ ~s(role="status")
    assert html =~ "Saved"
    assert html =~ ~s(aria-describedby="address-label-status")
    refute html =~ ~s(role="alert")
  end

  test "reports a refused commit as an alert on the field that caused it" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.inline_edit
        id="address-phone"
        value="+60 3"
        name="phone"
        label="Phone"
        status={{:error, "\"123\" was not saved: Phone should be at most 255 character(s)."}}
      />
      """)

    assert html =~ ~s(role="alert")
    assert html =~ "was not saved: Phone should be at most 255 character(s)."
    assert html =~ ~s(aria-invalid="true")
    # The stored value stays on screen; the rejected value only appears in the alert.
    assert html =~ ~s(value="+60 3")
    refute html =~ "Saved"
  end

  test "refuses a status it cannot report truthfully" do
    assigns = %{}

    assert_raise ArgumentError, ~r/status must be nil, :saved, or \{:error, message\}/, fn ->
      rendered_to_string(~H"""
      <.inline_edit id="x" value="v" status={:saving} />
      """)
    end
  end
end
