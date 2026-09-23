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

  Returning focus to the control that opened the dialog is the `Modal` hook's
  alone: no caller marks its opener, and the hook records the control the user
  activated rather than reading `document.activeElement`, which a browser that
  does not focus a `<button>` on click leaves on `<body>`. None of that is
  proven anywhere in this repository: it needs a real browser, there is no
  JavaScript test tooling here, and the hook's presence on every production
  dialog — which `assert_modal_dialog/3` does check — is not evidence that it
  returns focus. A reviewer confirms Escape, focus entry and focus return in a
  browser.

  The dialog's connection banners are checked through the encoded `phx-*`
  commands the LiveView client consumes — a serialized protocol, not source
  text — because that wiring is what a dropped socket executes to reveal them.
  Whether the revealed banner then paints above the dimmer and is announced
  inside the top layer is browser-only and unproven here.
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
      <.modal id="narrow" title="Narrow" on_cancel={JS.push("close")}>body</.modal>
      """)

    wide =
      rendered_to_string(~H"""
      <.modal id="wide" title="Wide" width={:wide} on_cancel={JS.push("close")}>body</.modal>
      """)

    compact =
      rendered_to_string(~H"""
      <.modal id="compact" title="Compact" width={:compact} on_cancel={JS.push("close")}>
        body
      </.modal>
      """)

    assert narrow =~ "max-w-lg"
    refute narrow =~ "max-w-2xl"
    assert wide =~ "max-w-2xl"
    refute wide =~ "max-w-lg"
    assert compact =~ "max-w-md"
    refute compact =~ "max-w-lg"
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

    assert [dialog_tag] = Regex.run(~r/<dialog[^>]*>/, with_flash)
    assert dialog_tag =~ "data-owns-flash"

    assert [plain_tag] = Regex.run(~r/<dialog[^>]*id="plain"[^>]*>/, without_flash)
    refute plain_tag =~ "data-owns-flash"
    refute without_flash =~ ~s(id="plain-flash-error")
    refute without_flash =~ ~s(id="plain-flash-info")
  end

  test "the dialog's connection banners carry the commands that reveal and hide them" do
    markup = render_modal(%{described: false})

    for kind <- ~w(client server) do
      id = "attach-modal-#{kind}-error"

      assert [tag] = Regex.run(~r/<div[^>]*id="#{id}"[^>]*>/, markup)
      assert tag =~ ~r/\shidden[\s>]/
      # The dialog's pair is the one that reports; the layout's yields to it.
      assert tag =~ ~r/\sdata-connection-banners[\s>]/
      refute tag =~ "data-yields"

      assert Enum.any?(banner_command(markup, id, "phx-disconnected"), fn
               ["remove_attr", %{"attr" => "hidden", "to" => to}] ->
                 to == ".phx-#{kind}-error ##{id}"

               _other ->
                 false
             end),
             "#{id} has no phx-disconnected command that unhides it"

      assert Enum.any?(banner_command(markup, id, "phx-connected"), fn
               ["set_attr", %{"attr" => ["hidden", ""]}] -> true
               _other -> false
             end),
             "#{id} has no phx-connected command that hides it again"
    end

    assert markup =~ "Reconnecting"
  end

  defp banner_command(markup, id, attribute) do
    assert [_, encoded] =
             Regex.run(~r/<div[^>]*id="#{id}"[^>]*#{attribute}="([^"]*)"/, markup)

    encoded
    |> String.replace("&quot;", ~s("))
    |> Jason.decode!()
  end
end
