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
end
