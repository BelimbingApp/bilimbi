defmodule Bilimbi.Base.UI.ComponentsConfirmDialogTest do
  @moduledoc """
  Tests for the shared <.confirm_dialog> component.

  A confirmation leads with the consequence: that sentence is the dialog's
  title and therefore its accessible name, the detail is its description, and
  the whole thing is an `alertdialog` built on the shared `<.modal>`, so it
  inherits the dialog semantics, the `Modal` hook and the Escape-to-cancel
  command that `components_modal_test.exs` covers.

  What is asserted here is the shape a caller cannot get wrong: Cancel before
  the confirm so focus lands on the safe action, the confirm as a calm danger
  text control that swaps to its in-flight label for the round trip, the two
  commands reaching their callers' handlers, and `busy` disabling Cancel while
  the confirm spins. Whether the browser focuses Cancel, keeps focus inside
  and returns it to the trigger is the native `<dialog>`'s and the hook's
  behaviour, confirmed in a browser rather than here.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Bilimbi.Base.UI.Components

  alias Phoenix.LiveView.JS

  defp render_confirm(assigns) do
    assigns = Map.put_new(assigns, :busy, false)

    rendered_to_string(~H"""
    <.confirm_dialog
      id="delete-type-confirm"
      consequence="Legal entity type “LLC” will be deleted."
      detail="It can no longer be chosen for a company. This cannot be undone."
      confirm="Delete"
      working="Deleting…"
      busy={@busy}
      on_confirm={JS.push("delete")}
      on_cancel={JS.push("cancel_delete")}
    />
    """)
  end

  test "is an alert dialog named by the consequence and described by the detail" do
    html = render_confirm(%{})

    assert [dialog_tag] = Regex.run(~r/<dialog[^>]*>/, html)
    assert dialog_tag =~ ~s(id="delete-type-confirm")
    assert dialog_tag =~ ~s(role="alertdialog")
    assert dialog_tag =~ ~s(aria-modal="true")
    assert dialog_tag =~ ~s(aria-labelledby="delete-type-confirm-title")
    assert dialog_tag =~ ~s(aria-describedby="delete-type-confirm-description")
    assert dialog_tag =~ ~s(phx-hook="Modal")
    assert dialog_tag =~ "max-w-md"

    assert html =~
             ~r/<h2 id="delete-type-confirm-title"[^>]*>\s*Legal entity type “LLC” will be deleted\.\s*<\/h2>/

    assert html =~
             ~r/<p id="delete-type-confirm-description"[^>]*>\s*It can no longer be chosen for a company\. This cannot be undone\.\s*<\/p>/
  end

  test "Escape and Cancel run the caller's cancel command; the confirm runs its action" do
    html = render_confirm(%{})

    cancel = ~s([[&quot;push&quot;,{&quot;event&quot;:&quot;cancel_delete&quot;}]])
    confirm = ~s([[&quot;push&quot;,{&quot;event&quot;:&quot;delete&quot;}]])

    assert html =~ ~s(data-cancel="#{cancel}")

    assert [cancel_tag] = Regex.run(~r/<button[^>]*id="delete-type-confirm-cancel"[^>]*>/, html)
    assert cancel_tag =~ ~s(phx-click="#{cancel}")
    refute cancel_tag =~ ~r/\sdisabled[\s>]/

    assert [confirm_tag] = Regex.run(~r/<button[^>]*id="delete-type-confirm-confirm"[^>]*>/, html)
    assert confirm_tag =~ ~s(phx-click="#{confirm}")
    assert confirm_tag =~ ~s(phx-disable-with="Deleting…")
    refute confirm_tag =~ "aria-busy"
  end

  test "Cancel comes before the confirm, and the confirm is calm danger text" do
    html = render_confirm(%{})

    {cancel_at, _} = :binary.match(html, ~s(id="delete-type-confirm-cancel"))
    {confirm_at, _} = :binary.match(html, ~s(id="delete-type-confirm-confirm"))
    assert cancel_at < confirm_at

    assert [confirm_tag] = Regex.run(~r/<button[^>]*id="delete-type-confirm-confirm"[^>]*>/, html)
    assert confirm_tag =~ ~r/\stext-danger[\s"]/
    # A solid fill (`bg-danger`) is the treatment DESIGN.md rules out; the
    # quiet hover surface (`hover:bg-danger-surface`) is the one it asks for.
    refute confirm_tag =~ ~r/\sbg-danger[\s"]/
    refute confirm_tag =~ "bg-action"

    assert html =~ ~r/id="delete-type-confirm-confirm"[^>]*>\s*Delete\s*<\/button>/
    assert html =~ ~r/id="delete-type-confirm-cancel"[^>]*>\s*Cancel\s*<\/button>/
  end

  test "busy spins the confirm and disables Cancel, because the action can no longer be stopped" do
    html = render_confirm(%{busy: true})

    assert [cancel_tag] = Regex.run(~r/<button[^>]*id="delete-type-confirm-cancel"[^>]*>/, html)
    assert cancel_tag =~ ~r/\sdisabled[\s>]/

    assert [confirm_tag] = Regex.run(~r/<button[^>]*id="delete-type-confirm-confirm"[^>]*>/, html)
    assert confirm_tag =~ ~s(aria-busy="true")
    assert confirm_tag =~ ~r/\sdisabled[\s>]/
  end

  test "the cancel label can name what is kept" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.confirm_dialog
        id="unlink-confirm"
        consequence="Head Office will be unlinked from Example Sdn Bhd."
        detail="The address itself is kept and can be attached again."
        confirm="Unlink"
        working="Unlinking…"
        cancel="Keep"
        on_confirm={JS.push("detach")}
        on_cancel={JS.push("cancel_detach")}
      />
      """)

    assert html =~ ~r/id="unlink-confirm-cancel"[^>]*>\s*Keep\s*<\/button>/
  end
end
