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
end
