defmodule Bilimbi.Base.UI.ComponentsModalTest do
  @moduledoc """
  Tests for the shared <.modal> component.

  The dialog semantics a screen reader and keyboard depend on are rendered
  here, not added by the browser: the element is a native `<dialog>` that is
  modal, named by its visible title, described by its optional description,
  and carries the `Modal` hook plus the cancel command the hook forwards to
  the server on Escape.

  A modal that omits `on_cancel` is caught by Phoenix's missing-required-
  attribute warning, which `mix precommit` turns into a build failure by
  compiling with `--warnings-as-errors`.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
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
      <.modal id="narrow" title="Narrow" on_cancel={JS.push("close")}>body</.modal>
      """)

    wide =
      rendered_to_string(~H"""
      <.modal id="wide" title="Wide" width={:wide} on_cancel={JS.push("close")}>body</.modal>
      """)

    assert narrow =~ "max-w-lg"
    refute narrow =~ "max-w-2xl"
    assert wide =~ "max-w-2xl"
    refute wide =~ "max-w-lg"
  end

  test "renders the caller's flash inside the dialog, and nothing when none is passed" do
    assigns = %{}

    with_flash =
      rendered_to_string(~H"""
      <.modal
        id="flashed"
        title="Flashed"
        flash={%{"error" => "Could not save the record."}}
        on_cancel={JS.push("close")}
      >
        body
      </.modal>
      """)

    without_flash =
      rendered_to_string(~H"""
      <.modal id="plain" title="Plain" on_cancel={JS.push("close")}>body</.modal>
      """)

    assert [dialog] = Regex.run(~r|<dialog[^>]*id="flashed".*?</dialog>|s, with_flash)
    assert dialog =~ ~s(id="flashed-flash-error")
    assert dialog =~ "Could not save the record."
    refute dialog =~ ~s(id="flashed-flash-info")

    refute without_flash =~ "flash"
  end

  test "a modal written without a cancel command warns that the attribute is missing" do
    warnings = compile_modal_probe("")

    assert warnings =~ ~s(missing required attribute "on_cancel")
  end

  test "a modal written with a cancel command raises no such warning" do
    warnings = compile_modal_probe(" on_cancel={Phoenix.LiveView.JS.push(\"close_probe\")}")

    refute warnings =~ "on_cancel"
  end

  defp compile_modal_probe(extra_attrs) do
    code = """
    defmodule Bilimbi.Base.UI.ModalCancelProbe#{System.unique_integer([:positive])} do
      use Phoenix.Component

      import Bilimbi.Base.UI.Components

      def render(assigns), do: ~H\"\"\"
      <.modal id="probe-modal" title="Probe"#{extra_attrs}>body</.modal>
      \"\"\"
    end
    """

    capture_io(:stderr, fn ->
      assert [_ | _] = Code.compile_string(code)
    end)
  end
end
