defmodule Bilimbi.Base.UITest do
  use ExUnit.Case, async: true

  describe "allowed?/2" do
    test "returns true when capability is in scope capabilities list" do
      scope = %{capabilities: ["admin.company.list", "admin.user.view"]}
      assert Bilimbi.Base.UI.allowed?(scope, "admin.company.list")
      assert Bilimbi.Base.UI.allowed?(scope, "admin.user.view")
    end

    test "returns false when capability is not in scope capabilities list" do
      scope = %{capabilities: ["admin.company.list"]}
      refute Bilimbi.Base.UI.allowed?(scope, "admin.user.delete")
    end

    test "returns false when capabilities is empty list" do
      scope = %{capabilities: []}
      refute Bilimbi.Base.UI.allowed?(scope, "admin.company.list")
    end

    test "returns false when capabilities is not a list" do
      refute Bilimbi.Base.UI.allowed?(%{capabilities: nil}, "admin.company.list")
      refute Bilimbi.Base.UI.allowed?(%{capabilities: "admin.company.list"}, "admin.company.list")
      refute Bilimbi.Base.UI.allowed?(%{capabilities: 123}, "admin.company.list")
    end

    test "returns false when scope is nil or not a map" do
      refute Bilimbi.Base.UI.allowed?(nil, "admin.company.list")
      refute Bilimbi.Base.UI.allowed?("not_a_map", "admin.company.list")
      refute Bilimbi.Base.UI.allowed?(123, "admin.company.list")
    end

    test "returns false when scope is a map without :capabilities key" do
      refute Bilimbi.Base.UI.allowed?(%{}, "admin.company.list")
      refute Bilimbi.Base.UI.allowed?(%{user: %{}}, "admin.company.list")
    end

    test "returns false when capability is not a binary string" do
      scope = %{capabilities: ["admin.company.list", :atom_cap]}
      refute Bilimbi.Base.UI.allowed?(scope, nil)
      refute Bilimbi.Base.UI.allowed?(scope, :admin_company_list)
      refute Bilimbi.Base.UI.allowed?(scope, 123)
    end
  end

  describe "current_user_id/1" do
    test "returns the id from the shape UserAuth.presentation_user/2 builds" do
      scope = %{
        user: %{
          "user_id" => 91,
          "name" => "Ada Lovelace",
          "email" => "ada@example.com",
          "company_id" => 73,
          "company_name" => "Bilimbi Industries"
        }
      }

      assert Bilimbi.Base.UI.current_user_id(scope) == 91
    end

    # Three adapters used to answer 0 for every one of these, which scoped
    # reads to a user that does not exist and made a broken scope look like an
    # account with no data. Each must now say so instead (#545).
    test "raises rather than defaulting when the scope carries no user id" do
      for scope <- [
            %{user: %{}},
            %{user: %{"name" => "Ada Lovelace"}},
            %{user: nil},
            %{},
            nil
          ] do
        assert_raise ArgumentError, ~r/no "user_id"/, fn ->
          Bilimbi.Base.UI.current_user_id(scope)
        end
      end
    end

    # The atom and string `id` keys the old cond arms probed for never occur --
    # they were dead branches. They must not quietly become live ones.
    test "does not accept an :id or \"id\" key as a substitute" do
      for scope <- [%{user: %{id: 91}}, %{user: %{"id" => 91}}] do
        assert_raise ArgumentError, fn -> Bilimbi.Base.UI.current_user_id(scope) end
      end
    end

    test "refuses a non-positive or non-integer id" do
      for scope <- [
            %{user: %{"user_id" => 0}},
            %{user: %{"user_id" => -1}},
            %{user: %{"user_id" => "91"}}
          ] do
        assert_raise ArgumentError, fn -> Bilimbi.Base.UI.current_user_id(scope) end
      end
    end
  end
end
