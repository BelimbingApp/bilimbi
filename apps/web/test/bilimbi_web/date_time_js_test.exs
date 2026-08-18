defmodule BilimbiWeb.DateTimeJsTest do
  use ExUnit.Case, async: true

  @hook Path.expand("../../assets/js/date_time.js", __DIR__)

  test "uses the operator's browser locale and hour cycle" do
    source = File.read!(@hook)

    assert source =~ "new Intl.DateTimeFormat(undefined, options)"
    refute source =~ "en-GB"
    refute source =~ "hourCycle"
  end
end
