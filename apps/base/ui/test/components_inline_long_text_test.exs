defmodule Bilimbi.Base.UI.ComponentsInlineLongTextTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  test "renders the read state and editor with the owner contract" do
    assigns = %{metadata_json: ~s({"tier": "gold"})}

    read =
      rendered_to_string(~H"""
      <.inline_long_text
        id="company-metadata"
        field="metadata"
        label="Company metadata JSON"
        value={@metadata_json}
        editing={false}
        editable?
        save_event="save_metadata"
        allow_empty
        rows={5}
        status={nil}
      />
      """)

    assert read =~ ~s(phx-hook="InlineLongText")
    assert read =~ ~s(data-value="{&quot;tier&quot;: &quot;gold&quot;}")
    assert read =~ ~s(id="company-metadata-display")
    assert read =~ ~s(phx-click="edit_field")
    assert read =~ "tier"
    refute read =~ ~s(id="company-metadata-input")

    editing =
      rendered_to_string(~H"""
      <.inline_long_text
        id="company-metadata"
        field="metadata"
        label="Company metadata JSON"
        value={@metadata_json}
        editing
        editable?
        save_event="save_metadata"
        edit_event="edit_metadata"
        cancel_event="cancel_edit_metadata"
        allow_empty
        rows={5}
        status={{:error, "Invalid JSON"}}
      />
      """)

    assert editing =~ ~s(phx-window-keydown="cancel_edit_metadata")
    assert editing =~ ~s(id="company-metadata-input")
    assert editing =~ ~s(name="metadata")
    assert editing =~ ~s(rows="5")
    assert editing =~ ~s(aria-invalid="true")
    assert editing =~ ~s(id="company-metadata-status" role="alert")
    assert editing =~ "Invalid JSON"
  end

  test "reports a saved state and renders no editing affordance for read-only facts" do
    assigns = %{description: "Several lines\nof useful detail."}

    html =
      rendered_to_string(~H"""
      <.inline_long_text
        id="description"
        field="description"
        label="Description"
        value={@description}
        editing={false}
        editable?={false}
        save_event="save_description"
        status={:saved}
      />
      """)

    assert html =~ ~s(whitespace-pre-wrap)
    assert html =~ ~s(id="description-status" role="status")
    assert html =~ "Saved"
    refute html =~ ~s(phx-click="edit_field")
    refute html =~ ~s(data-role="input")
  end
end
