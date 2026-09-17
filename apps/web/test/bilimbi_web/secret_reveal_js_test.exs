defmodule BilimbiWeb.SecretRevealJsTest do
  use ExUnit.Case, async: true

  @hook Path.expand("../../assets/js/secret_reveal.js", __DIR__)
  @app Path.expand("../../assets/js/app.js", __DIR__)

  test "the hook keeps a pointer press on the toggle from taking focus or moving the caret" do
    source = File.read!(@hook)

    # A source grep, because this file has no JS runtime. The toggle itself
    # is a LiveView JS command so it stays sticky across patches; the hook
    # exists only so a mouse click on the eye leaves the user typing where
    # they were: focus stays in the input, and the selection the type swap
    # resets is put back once the command has run.
    assert source =~ "addEventListener(\"mousedown\", (e) => e.preventDefault())"
    assert source =~ "document.activeElement !== input) return"

    assert source =~
             "setTimeout(() => input.setSelectionRange(selectionStart, selectionEnd), 0)"

    refute source =~ "setAttribute",
           "attribute swaps belong to the JS command, or a patch reverts them"

    refute source =~ "pushEvent", "revealing a secret is client-only; nothing goes to the server"
  end

  test "the hook is registered with the LiveSocket under the name the component uses" do
    source = File.read!(@app)

    assert source =~ ~s(import SecretReveal from "./secret_reveal")
    assert source =~ ~r/hooks: \{[^}]*SecretReveal[^}]*\}/
  end
end
