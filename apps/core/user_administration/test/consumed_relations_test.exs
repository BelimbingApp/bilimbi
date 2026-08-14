defmodule Bilimbi.Core.UserAdministration.ConsumedRelationsTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Core.UserAdministration.ConsumedRelations

  test "version 1 matches every reviewed owner contract" do
    assert ConsumedRelations.contract_version() == 1
    assert :ok = ConsumedRelations.verify!()

    assert Enum.map(ConsumedRelations.manifest(), &{&1.owner, &1.relation}) == [
             {"core/user", "users"},
             {"core/company", "companies"},
             {"base/authz", "base_authz_principal_roles"},
             {"base/authz", "base_authz_roles"}
           ]
  end

  test "the verifier rejects a version, type, nullability, relation, or column drift" do
    [user | rest] = ConsumedRelations.manifest()

    drifts = [
      [%{user | migration_version: 0} | rest],
      [%{user | relation: "renamed_users"} | rest],
      [%{user | columns: Map.put(user.columns, "id", %{type: :integer, nullable: false})} | rest],
      [%{user | columns: Map.put(user.columns, "id", %{type: :bigint, nullable: true})} | rest],
      [
        %{user | columns: Map.put(user.columns, "password", %{type: :text, nullable: false})}
        | rest
      ]
    ]

    Enum.each(drifts, fn manifest ->
      assert_raise RuntimeError, ~r/consumed relation contract drift/, fn ->
        ConsumedRelations.verify!(manifest)
      end
    end)
  end
end
