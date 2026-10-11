defmodule Bilimbi.Base.Media.MaintenanceTaskTest do
  use ExUnit.Case, async: true

  test "requires an explicit tenant and positive whole-number hours before starting applications" do
    for args <- [
          [],
          ["--tenant", "1", "--hours", "0"],
          ["--tenant", "1", "--hours", "1.5"],
          ["--tenant", "0"],
          ["--all"],
          ["--tenant", "1", "unexpected"]
        ] do
      assert_raise Mix.Error, ~r/usage:/, fn ->
        Mix.Tasks.Bilimbi.Media.Attachments.Cleanup.run(args)
      end
    end
  end
end
