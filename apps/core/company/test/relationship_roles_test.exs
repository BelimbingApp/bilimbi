defmodule Bilimbi.Core.Company.RelationshipRolesTest do
  use Bilimbi.Base.Database.DataCase, async: true
  alias Bilimbi.Base.{Repo, Tenancy}
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.RelationshipCatalogue
  alias Bilimbi.Core.Company.Relationships
  import Bilimbi.Core.Company.TestFixtures
  import Bilimbi.Base.Database.TestHelpers, only: [errors_on: 1]

  setup do
    create_company_identity_tables!()
    create_external_access_tables!()
    insert_tenant!()
    insert_tenant!(%{id: 42, is_platform_operator: false})
    insert_company!()
    insert_company!(%{id: 74, code: "supplier", name: "Supplier"})
    insert_company!(%{id: 75, code: "foreign", tenant_id: 42})
    :ok = RelationshipCatalogue.ensure_defaults(Repo)
    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  test "default roles coexist and have explicit inverse semantics without portal grants", %{
    scope: scope
  } do
    {:ok, roles} = Company.list_relationship_types()
    vendor = Enum.find(roles, &(&1.code == "vendor"))
    customer = Enum.find(roles, &(&1.code == "customer"))

    assert {:ok, v} =
             Company.create_relationship(scope, 73, %{
               related_company_id: 74,
               relationship_type_id: vendor.id
             })

    assert {:ok, c} =
             Company.create_relationship(scope, 73, %{
               related_company_id: 74,
               relationship_type_id: customer.id
             })

    refute v.id == c.id
    assert {:ok, outgoing} = Company.list_relationships(scope, 73)

    assert MapSet.new(Enum.map(outgoing, & &1.role_label)) ==
             MapSet.new(["Vendor / Supplier", "Customer"])

    assert {:ok, incoming} = Company.list_relationships(scope, 74)
    assert Enum.find(incoming, &(&1.id == v.id)).role_label == "Customer"
    assert Enum.find(incoming, &(&1.id == c.id)).role_label == "Vendor / Supplier"
    assert Repo.aggregate(Bilimbi.Core.Company.ExternalAccess, :count) == 0
  end

  test "forged source and cross-tenant targets cannot change relationship ownership", %{
    scope: scope
  } do
    {:ok, [role | _]} = Company.list_relationship_types()

    assert {:error, :company_not_found} =
             Company.create_relationship(scope, 73, %{
               related_company_id: 75,
               relationship_type_id: role.id
             })

    assert {:ok, rel} =
             Company.create_relationship(scope, 73, %{
               company_id: 75,
               related_company_id: 74,
               relationship_type_id: role.id
             })

    assert rel.company_id == 73
  end

  test "reference seeding preserves operator rename and retirement", %{scope: scope} do
    {:ok, roles} = Company.list_relationship_types()
    role = Enum.find(roles, &(&1.code == "vendor"))
    Repo.update!(Ecto.Changeset.change(role, name: "Preferred supplier", is_active: false))
    assert :ok = RelationshipCatalogue.ensure_defaults(Repo)

    assert {:ok, %{name: "Preferred supplier", is_active: false}} =
             Company.get_relationship_type(role.id)

    assert {:error, %Ecto.Changeset{}} =
             Company.create_relationship(scope, 73, %{
               related_company_id: 74,
               relationship_type_id: role.id
             })
  end

  describe "live relationship uniqueness" do
    setup do
      {:ok, roles} = Company.list_relationship_types()
      %{vendor: Enum.find(roles, &(&1.code == "vendor"))}
    end

    defp attrs(vendor, extra \\ %{}),
      do: Map.merge(%{related_company_id: 74, relationship_type_id: vendor.id}, extra)

    test "a replayed assignment is refused, dated or not", %{scope: scope, vendor: vendor} do
      assert {:ok, _} = Company.create_relationship(scope, 73, attrs(vendor))

      for extra <- [%{}, %{effective_from: ~D[2026-10-14]}] do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Company.create_relationship(scope, 73, attrs(vendor, extra))

        assert %{relationship_type_id: ["is already assigned between these companies"]} =
                 errors_on(changeset)
      end

      assert {:ok, [_only_one]} = Company.list_relationships(scope, 73)
    end

    test "preview refuses what commit would duplicate", %{scope: scope, vendor: vendor} do
      input = %{"related_company_id" => 74, "relationship_type_id" => vendor.id}
      assert {:ok, _} = Relationships.preview(scope, 73, nil, "create", input)
      assert {:ok, _} = Company.create_relationship(scope, 73, attrs(vendor))
      assert {:error, %Ecto.Changeset{}} = Relationships.preview(scope, 73, nil, "create", input)
    end

    test "ended and unlinked links stay history and allow a later link", %{
      scope: scope,
      vendor: vendor
    } do
      assert {:ok, ended} =
               Company.create_relationship(
                 scope,
                 73,
                 attrs(vendor, %{effective_from: ~D[2025-01-01], effective_to: ~D[2025-12-31]})
               )

      assert {:ok, current} = Company.create_relationship(scope, 73, attrs(vendor))
      assert :ok = Company.delete_relationship(scope, 73, current.id)
      assert {:ok, again} = Company.create_relationship(scope, 73, attrs(vendor))

      assert {:ok, rows} = Company.list_relationships(scope, 73, include_unlinked: true)
      assert MapSet.new(Enum.map(rows, & &1.id)) == MapSet.new([ended.id, current.id, again.id])
    end

    test "reopening an ended link cannot duplicate the open one", %{scope: scope, vendor: vendor} do
      assert {:ok, ended} =
               Company.create_relationship(
                 scope,
                 73,
                 attrs(vendor, %{effective_from: ~D[2025-01-01], effective_to: ~D[2025-12-31]})
               )

      assert {:ok, _open} = Company.create_relationship(scope, 73, attrs(vendor))

      assert {:error, %Ecto.Changeset{} = changeset} =
               Company.update_relationship(scope, 73, ended.id, %{effective_to: nil})

      assert %{effective_to: ["is already assigned between these companies"]} =
               errors_on(changeset)
    end

    test "preview of reopening an ended link refuses what commit would refuse", %{
      scope: scope,
      vendor: vendor
    } do
      assert {:ok, ended} =
               Company.create_relationship(
                 scope,
                 73,
                 attrs(vendor, %{effective_from: ~D[2025-01-01], effective_to: ~D[2025-12-31]})
               )

      assert {:ok, open} = Company.create_relationship(scope, 73, attrs(vendor))
      clear = %{"effective_to" => nil}

      assert {:error, %Ecto.Changeset{}} =
               Relationships.preview(scope, 73, ended.id, "update", clear)

      assert {:ok, _} = Relationships.preview(scope, 73, open.id, "update", clear)
    end

    test "the same role in the opposite direction is a different link", %{
      scope: scope,
      vendor: vendor
    } do
      assert {:ok, _} = Company.create_relationship(scope, 73, attrs(vendor))

      assert {:ok, _} =
               Company.create_relationship(scope, 74, %{
                 related_company_id: 73,
                 relationship_type_id: vendor.id
               })
    end
  end
end
