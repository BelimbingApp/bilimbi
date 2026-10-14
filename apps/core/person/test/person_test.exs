defmodule Bilimbi.Core.PersonTest do
  use Bilimbi.Base.Database.DataCase, async: true
  alias Bilimbi.Core.Person
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Base.Tenancy

  setup do
    # No employees or People tables exist: these contracts work without HR.
    CompanyFixtures.create_company_identity_tables!()
    Bilimbi.Core.Person.TestFixtures.create_person_tables!()
    CompanyFixtures.insert_tenant!()
    CompanyFixtures.insert_tenant!(%{id: 42, is_platform_operator: false})
    CompanyFixtures.insert_company!()
    CompanyFixtures.insert_company!(%{id: 74, code: "vendor", name: "Vendor"})
    CompanyFixtures.insert_company!(%{id: 75, tenant_id: 42, code: "foreign"})
    {:ok, scope} = Tenancy.scope(41)
    {:ok, foreign} = Tenancy.scope(42)
    %{scope: scope, foreign: foreign}
  end

  test "namecard creates only identity and affiliation, supports searching and reuse", %{
    scope: scope
  } do
    assert {:ok, %{person: person, affiliation: affiliation}} =
             Person.create_contact(scope, 74, %{
               full_name: "Vendor Vera",
               title: "Sales",
               email: "vera@vendor.test",
               phone: "+60123"
             })

    assert affiliation.company_id == 74
    assert affiliation.title == "Sales"
    assert affiliation.legacy_employee_id == nil
    refute Map.has_key?(person, :employee_number)
    refute Map.has_key?(person, :employee_type)
    refute Map.has_key?(person, :status)
    refute Map.has_key?(person, :user_id)

    assert {:ok, %{entries: [%{id: id}], total: 1}} =
             Person.list(scope, search: "vera@vendor.test")

    assert id == person.id
    assert {:ok, second} = Person.link(scope, person.id, 73, %{title: "Adviser"})
    assert second.person_id == person.id
    assert {:ok, fetched} = Person.get(scope, person.id)
    assert length(fetched.affiliations) == 2
  end

  test "HR fields are refused; tenant and person IDs are never cast from attributes", %{
    scope: scope
  } do
    for field <- ~w(employee_number employee_type status employment_start user_id) do
      assert {:error, :hr_fields_not_supported} =
               Person.create(scope, %{"full_name" => "Vera", field => "invented"})
    end

    assert {:ok, person} = Person.create(scope, %{full_name: "Safe", tenant_id: 42, id: 500})
    refute person.id == 500
    assert {:ok, _} = Person.get(scope, person.id)
  end

  test "cross-tenant reads and writes are denied without leaking identity", %{
    scope: scope,
    foreign: foreign
  } do
    {:ok, %{person: person, affiliation: a}} =
      Person.create_contact(scope, 74, %{full_name: "Vera"})

    assert {:error, :not_found} = Person.get(foreign, person.id)
    assert {:error, :not_found} = Person.update(foreign, person.id, %{full_name: "Stolen"})
    assert {:error, :not_found} = Person.unlink(foreign, person.id, a.id)
    assert {:error, :not_found} = Person.link(scope, person.id, 75, %{})
    assert {:ok, %{entries: [], total: 0}} = Person.list(foreign)
  end

  test "unlink and retirement retain records; a person can be linked again", %{scope: scope} do
    {:ok, %{person: person, affiliation: a}} =
      Person.create_contact(scope, 74, %{full_name: "Vera"})

    assert {:ok, %{unlinked_at: %NaiveDateTime{}}} = Person.unlink(scope, person.id, a.id)
    assert {:ok, second} = Person.link(scope, person.id, 74, %{title: "Director"})
    refute second.id == a.id
    assert {:ok, %{affiliations: rows}} = Person.get(scope, person.id)
    assert length(rows) == 2
    assert {:ok, _} = Person.retire(scope, person.id)
    assert {:ok, %{entries: []}} = Person.list(scope)
    assert {:ok, %{affiliations: [_, _]}} = Person.get(scope, person.id)
    assert {:error, :person_retired} = Person.update(scope, person.id, %{full_name: "Later"})
  end

  test "preview is nonmutating and lifecycle previews are stable", %{scope: scope} do
    input = %{"company_id" => 74, "full_name" => "Vera", "title" => "Sales"}
    assert {:ok, preview} = Person.preview(scope, :contact, input)
    assert Enum.any?(preview.changes, &(&1.field == "title" and &1.to == "Sales"))
    assert {:ok, %{entries: []}} = Person.list(scope)
    {:ok, %{person: p}} = Person.create_contact(scope, 74, input)
    assert {:ok, first} = Person.preview(scope, :retire, %{"person_id" => p.id})
    assert {:ok, ^first} = Person.preview(scope, :retire, %{"person_id" => p.id})
  end

  test "PostgreSQL refuses an affiliation carrying another tenant's person", %{scope: scope} do
    {:ok, person} = Person.create(scope, %{full_name: "Vera"})

    assert_raise Ecto.ConstraintError, fn ->
      Bilimbi.Base.Repo.insert!(%Bilimbi.Core.Person.Affiliation{
        tenant_id: 42,
        person_id: person.id,
        company_id: 75
      })
    end
  end

  test "duplicate search includes contact details added only to an affiliation", %{scope: scope} do
    {:ok, person} = Person.create(scope, %{full_name: "Vera"})

    {:ok, _} =
      Person.link(scope, person.id, 74, %{email: "work-only@vendor.test", phone: "555-947"})

    assert {:ok, %{entries: [%{id: id}], total: 1}} =
             Person.list(scope, search: "work-only@vendor.test")

    assert id == person.id
    assert {:ok, %{entries: [%{id: ^id}]}} = Person.list(scope, search: "555-947")
  end
end
