defmodule BilimbiWeb.FlashAutoDismissJsTest do
  @moduledoc """
  Source guards for the `FlashAutoDismiss` hook. There is no JS runtime in
  this suite, so these read the file for the two properties the flash
  contract depends on: a timed dismissal leaves the same state as a clicked
  one, and reading a message pauses its timer.
  """

  use ExUnit.Case, async: true

  @hook Path.expand("../../assets/js/flash_auto_dismiss.js", __DIR__)
  @app Path.expand("../../assets/js/app.js", __DIR__)

  test "the hook is registered with the live socket" do
    assert File.read!(@app) =~ "FlashAutoDismiss"
  end

  test "a timed dismissal runs the message's own click command" do
    source = File.read!(@hook)

    assert source =~ "getAttribute(\"phx-click\")",
           "the timer must reuse the click command, so the server flash is cleared too"

    assert source =~ "execJS(this.el, command"
  end

  test "the pointer or focus on the message pauses the timer" do
    source = File.read!(@hook)

    for event <- ~w(mouseenter focusin mouseleave focusout) do
      assert source =~ "addEventListener(\"#{event}\""
    end

    assert source =~ "destroyed()"
    assert source =~ "clearTimeout"
  end
end
