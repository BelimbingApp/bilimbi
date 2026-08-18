defmodule BilimbiWeb.InlineEditJsTest do
  use ExUnit.Case, async: true

  @hook Path.expand("../../assets/js/inline_edit.js", __DIR__)

  test "inline_edit hook handles startEdit, commit on blur/Enter, cancel on Escape" do
    source = File.read!(@hook)

    assert source =~ "startEdit()"
    assert source =~ "commit()"
    assert source =~ "cancel()"
    assert source =~ ~s(addEventListener("blur")
    assert source =~ ~s(this.pushEvent(saveEvent)
  end

  test "the hook never writes the displayed text itself" do
    source = File.read!(@hook)

    # A source grep, because this file has no JS runtime. The property it
    # protects is real: painting the text client-side made a FAILED save look
    # successful, since the error branch sends no patch (#302). The server owns
    # the value; the hook only sends the event.
    refute source =~ "textEl.textContent =",
           """
           The hook is writing the display text again.

           On a failed save nothing patches the row, so the optimistic text
           stays and the screen contradicts its own flash.
           """
  end

  test "syncValue leaves an open editor alone and reads the server's value" do
    source = File.read!(@hook)

    # Plain strings, not ~s(): the code under test contains unbalanced
    # parentheses, which close the sigil early and stop this file compiling.
    assert source =~ "classList.contains(\"hidden\")) return",
           "syncValue must bail out mid-edit, or a patch publishes half-typed text"

    assert source =~ "getAttribute(\"value\")",
           "syncValue must read the attribute; .value decouples once a user types"
  end
end
