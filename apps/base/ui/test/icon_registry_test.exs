defmodule Bilimbi.Base.UI.IconRegistryTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.IconRegistry

  test "provides the product pin when Heroicons has no matching glyph" do
    assert {:ok, icon} = IconRegistry.fetch("bilimbi-pin")
    assert icon.view_box == "0 0 24 24"
    assert icon.fill == "none"
    assert length(icon.paths) == 2
  end

  test "provides the product impersonate icon" do
    assert {:ok, icon} = IconRegistry.fetch("bilimbi-impersonate")
    assert icon.view_box == "0 0 24 24"
    assert icon.fill == "none"
    assert length(icon.paths) == 4

    assert {:ok, hero_icon} = IconRegistry.fetch("hero-impersonate")
    assert hero_icon == icon
  end

  test "does not claim arbitrary icon names" do
    assert :error = IconRegistry.fetch("unknown-icon")
  end
end
