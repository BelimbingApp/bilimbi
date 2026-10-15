defmodule Bilimbi.Core.PersonRelationshipsTest do
  use Bilimbi.Base.Database.DataCase, async: true
  alias Bilimbi.Base.{Repo, Tenancy}
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.RelationshipCatalogue
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Person
  import Bilimbi.Base.Database.TestHelpers, only: [errors_on: 1]

  setup do
    CompanyFixtures.create_company_identity_tables!()
    CompanyFixtures.create_external_access_tables!()
    Person.TestFixtures.create_person_tables!()
    CompanyFixtures.insert_tenant!()
    CompanyFixtures.insert_tenant!(%{id: 42, is_platform_operator: false})
    CompanyFixtures.insert_company!()
    CompanyFixtures.insert_company!(%{id: 75, tenant_id: 42, code: "foreign"})
    :ok = RelationshipCatalogue.ensure_defaults(Repo)
    {:ok, scope} = Tenancy.scope(41)
    {:ok, foreign} = Tenancy.scope(42)
    {:ok, roles} = Company.list_relationship_types()
    {:ok, lead} = Person.create(scope, %{full_name: "Lena Lead", email: "lena@lead.test"})
    %{scope: scope, foreign: foreign, lead: lead, roles: Map.new(roles, &{&1.code, &1})}
  end

  test "prospect is a default role", %{roles: roles} do
    assert %{name: "Prospect", is_active: true} = roles["prospect"]
  end

  test "a bare person is a prospect, then a customer, with history kept", %{
    scope: scope,
    lead: lead,
    roles: roles
  } do
    assert {:ok, prospect} =
             Person.create_relationship(scope, lead.id, 73, %{
               relationship_type_id: roles["prospect"].id,
               effective_from: "2026-01-01"
             })

    assert prospect.role_label == "Prospect"
    assert prospect.is_active
    assert {:ok, [^prospect]} = Person.relationships(scope, lead.id)

    assert {:ok, ended} = Person.unlink_relationship(scope, lead.id, prospect.id)
    assert ended.unlinked_at

    assert {:ok, customer} =
             Person.create_relationship(scope, lead.id, 73, %{
               relationship_type_id: roles["customer"].id
             })

    assert {:ok, [only]} = Person.relationships(scope, lead.id)
    assert only.id == customer.id
    assert {:ok, history} = Person.relationships(scope, lead.id, include_unlinked: true)
    assert [prospect.id, customer.id] == Enum.map(history, & &1.id)
    assert Repo.aggregate(Company.Relationship, :count) == 0
    assert {:ok, %{affiliations: []}} = Person.get(scope, lead.id)
  end

  test "a person can hold several concurrent roles toward a company", %{
    scope: scope,
    lead: lead,
    roles: roles
  } do
    for code <- ["customer", "vendor"] do
      assert {:ok, _} =
               Person.create_relationship(scope, lead.id, 73, %{
                 relationship_type_id: roles[code].id
               })
    end

    assert {:ok, rows} = Person.relationships(scope, lead.id)
    assert Enum.sort(Enum.map(rows, & &1.role_code)) == ["customer", "vendor"]
    assert Enum.find(rows, &(&1.role_code == "vendor")).inverse_label == "Customer"
  end

  test "a live duplicate and a retired role are refused; dated updates keep identity", %{
    scope: scope,
    lead: lead,
    roles: roles
  } do
    attrs = %{relationship_type_id: roles["customer"].id}
    assert {:ok, rel} = Person.create_relationship(scope, lead.id, 73, attrs)

    assert {:error, cs} = Person.create_relationship(scope, lead.id, 73, attrs)
    assert %{relationship_type_id: [_]} = errors_on(cs)

    assert {:ok, updated} =
             Person.update_relationship(scope, lead.id, rel.id, %{effective_to: "2030-12-31"})

    assert updated.id == rel.id and updated.role_code == "customer"

    assert {:error, cs} =
             Person.update_relationship(scope, lead.id, rel.id, %{effective_from: "2031-01-01"})

    assert %{effective_to: [_]} = errors_on(cs)

    Repo.update!(Ecto.Changeset.change(roles["partner"], is_active: false))

    assert {:error, cs} =
             Person.create_relationship(scope, lead.id, 73, %{
               relationship_type_id: roles["partner"].id
             })

    assert %{relationship_type_id: [_]} = errors_on(cs)
  end

  test "unlinked, retired and cross-tenant targets are refused", %{
    scope: scope,
    foreign: foreign,
    lead: lead,
    roles: roles
  } do
    attrs = %{relationship_type_id: roles["customer"].id}
    assert {:ok, rel} = Person.create_relationship(scope, lead.id, 73, attrs)
    assert {:error, :not_found} = Person.create_relationship(scope, lead.id, 75, attrs)
    assert {:error, :not_found} = Person.relationships(foreign, lead.id)
    assert {:error, :not_found} = Person.unlink_relationship(foreign, lead.id, rel.id)
    assert {:error, :company_not_found} = Person.create_relationship(scope, lead.id, nil, attrs)

    assert {:ok, _} = Person.unlink_relationship(scope, lead.id, rel.id)

    assert {:error, :relationship_unlinked} =
             Person.update_relationship(scope, lead.id, rel.id, %{effective_to: "2030-01-01"})

    assert {:ok, _} = Person.retire(scope, lead.id)
    assert {:error, :person_retired} = Person.create_relationship(scope, lead.id, 73, attrs)
  end

  test "ids and tenant are never cast; PostgreSQL refuses another tenant's person", %{
    scope: scope,
    lead: lead,
    roles: roles
  } do
    assert {:ok, rel} =
             Person.create_relationship(scope, lead.id, 73, %{
               relationship_type_id: roles["customer"].id,
               tenant_id: 42,
               person_id: 999,
               company_id: 75
             })

    assert {rel.person_id, rel.company_id} == {lead.id, 73}

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%Person.Relationship{
        tenant_id: 42,
        person_id: lead.id,
        company_id: 75,
        relationship_type_id: roles["customer"].id
      })
    end
  end

  test "preview is nonmutating and validates like the commit", %{
    scope: scope,
    lead: lead,
    roles: roles
  } do
    input = %{
      "person_id" => lead.id,
      "company_id" => 73,
      "relationship_type_id" => roles["prospect"].id
    }

    assert {:ok, preview} = Person.preview(scope, :relationship_create, input)
    assert Enum.any?(preview.changes, &(&1.field == "company_id" and &1.to == 73))
    assert {:ok, []} = Person.relationships(scope, lead.id)

    assert {:error, %Ecto.Changeset{}} =
             Person.preview(
               scope,
               :relationship_create,
               Map.put(input, "relationship_type_id", 0)
             )

    {:ok, rel} =
      Person.create_relationship(scope, lead.id, 73, %{relationship_type_id: roles["prospect"].id})

    assert {:ok, %{changes: changes}} =
             Person.preview(scope, :relationship_unlink, %{
               "person_id" => lead.id,
               "relationship_id" => rel.id
             })

    assert Enum.any?(changes, &(&1.field == "deleted_at" and &1.to == "recorded at commit"))
    assert {:ok, [_]} = Person.relationships(scope, lead.id)
  end
end
