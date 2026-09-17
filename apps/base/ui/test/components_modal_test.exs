defmodule Bilimbi.Base.UI.ComponentsModalTest do
  @moduledoc """
  Tests for the shared <.modal> component.

  The dialog semantics a screen reader and keyboard depend on are rendered
  here, not added by the browser: the element is a native `<dialog>` that is
  modal, named by its visible title, described by its optional description,
  and carries the `Modal` hook plus the cancel command the hook forwards to
  the server on Escape.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  alias Phoenix.LiveView.JS

  defp render_modal(assigns) do
    rendered_to_string(~H"""
    <.modal id="attach-modal" title="Attach Address" on_cancel={JS.push("close_attach")}>
      <:description :if={@described}>Select an address to attach.</:description>
      <button type="button" phx-click="close_attach">Cancel</button>
    </.modal>
    """)
  end

  test "renders an open modal dialog named by its title and described by its description" do
    html = render_modal(%{described: true})

    assert [dialog_tag] = Regex.run(~r/<dialog[^>]*>/, html)
    assert dialog_tag =~ ~s(id="attach-modal")
    assert dialog_tag =~ ~r/\sopen[\s>]/
    assert dialog_tag =~ ~s(aria-modal="true")
    assert dialog_tag =~ ~s(aria-labelledby="attach-modal-title")
    assert dialog_tag =~ ~s(aria-describedby="attach-modal-description")
    assert dialog_tag =~ ~s(phx-hook="Modal")
    assert dialog_tag =~ ~s(tabindex="-1")

    assert html =~ ~r/<h2 id="attach-modal-title"[^>]*>\s*Attach Address\s*<\/h2>/

    assert html =~
             ~r/<p id="attach-modal-description"[^>]*>\s*Select an address to attach\.\s*<\/p>/

    assert html =~ ~s(phx-click="close_attach">Cancel</button>)
  end

  test "omits the description reference when no description is given" do
    html = render_modal(%{described: false})

    refute html =~ "aria-describedby"
    refute html =~ "attach-modal-description"
  end

  test "carries the cancel command the hook runs on Escape" do
    html = render_modal(%{described: true})

    assert html =~
             ~s(data-cancel="[[&quot;push&quot;,{&quot;event&quot;:&quot;close_attach&quot;}]]")
  end

  test "widens the panel only when asked" do
    assigns = %{}

    narrow =
      rendered_to_string(~H"""
      <.modal id="narrow" title="Narrow">body</.modal>
      """)

    wide =
      rendered_to_string(~H"""
      <.modal id="wide" title="Wide" width={:wide}>body</.modal>
      """)

    assert narrow =~ "max-w-lg"
    refute narrow =~ "max-w-2xl"
    assert wide =~ "max-w-2xl"
    refute wide =~ "max-w-lg"
  end
end
