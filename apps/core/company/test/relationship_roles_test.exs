defmodule Bilimbi.Core.Company.RelationshipRolesTest do
  use Bilimbi.Base.Database.DataCase, async: true
  alias Bilimbi.Base.{Repo, Tenancy}
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.RelationshipCatalogue
  import Bilimbi.Core.Company.TestFixtures

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
end
