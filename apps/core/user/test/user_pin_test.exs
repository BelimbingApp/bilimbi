defmodule Bilimbi.Core.User.PinTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Pin
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    UserFixtures.create_user_pins_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    UserFixtures.insert_user!(%{
      id: 91,
      company_id: 73,
      name: "Ada Lovelace",
      email: "ada@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    :ok
  end

  describe "URL and label normalization" do
    test "normalize_label extracts leaf segment from breadcrumb path" do
      assert Pin.normalize_label("Admin / System / General") == "General"
      assert Pin.normalize_label("Users / Edit") == "Edit"
      assert Pin.normalize_label("Companies") == "Companies"
      assert Pin.normalize_label("  Trailing Spaces / Leaf  ") == "Leaf"
    end

    test "normalize_url normalizes path and sorts query params deterministically" do
      assert Pin.normalize_url("/companies") == "/companies"
      assert Pin.normalize_url("/companies/") == "/companies"
      assert Pin.normalize_url("https://example.com/companies?b=2&a=1") == "/companies?a=1&b=2"
      assert Pin.normalize_url("/settings/profile#section") == "/settings/profile"
    end

    test "hash_url returns MD5 hex digest of normalized url" do
      hash1 = Pin.hash_url("/companies?a=1&b=2")
      hash2 = Pin.hash_url("https://example.com/companies/?b=2&a=1")
      assert hash1 == hash2
      assert String.length(hash1) == 32
    end
  end

  describe "pin persistence & lifecycle" do
    test "toggle_user_pin creates and deletes pins" do
      assert {:ok, :pinned, pins} =
               User.toggle_user_pin(91, %{
                 "label" => "Companies",
                 "url" => "/companies",
                 "icon" => "hero-building-office"
               })

      assert length(pins) == 1
      assert hd(pins).label == "Companies"
      assert hd(pins).url == "/companies"
      assert hd(pins).sort_order == 0

      # Toggling the same URL deletes the pin
      assert {:ok, :unpinned, pins} =
               User.toggle_user_pin(91, %{
                 "label" => "Companies",
                 "url" => "/companies"
               })

      assert pins == []
    end

    test "toggle_user_pin calculates incremental sort orders" do
      assert {:ok, :pinned, _} =
               User.toggle_user_pin(91, %{"label" => "Pin 1", "url" => "/page1"})

      assert {:ok, :pinned, pins} =
               User.toggle_user_pin(91, %{"label" => "Pin 2", "url" => "/page2"})

      assert length(pins) == 2
      [pin1, pin2] = pins
      assert pin1.sort_order == 0
      assert pin2.sort_order == 1
    end

    test "reorder_user_pins updates sort orders matching list position" do
      {:ok, :pinned, _} = User.toggle_user_pin(91, %{"label" => "Pin 1", "url" => "/page1"})

      {:ok, :pinned, [pin1, pin2]} =
        User.toggle_user_pin(91, %{"label" => "Pin 2", "url" => "/page2"})

      assert {:ok, reordered} = User.reorder_user_pins(91, [pin2.id, pin1.id])
      assert Enum.map(reordered, & &1.id) == [pin2.id, pin1.id]
      assert Enum.map(reordered, & &1.sort_order) == [0, 1]
    end

    test "pins are isolated between users" do
      {:ok, :pinned, _} = User.toggle_user_pin(91, %{"label" => "Ada's Page", "url" => "/page"})
      {:ok, :pinned, _} = User.toggle_user_pin(92, %{"label" => "Grace's Page", "url" => "/page"})

      assert [ada_pin] = User.list_user_pins(91)
      assert [grace_pin] = User.list_user_pins(92)
      assert ada_pin.label == "Ada's Page"
      assert grace_pin.label == "Grace's Page"
    end
  end
end
