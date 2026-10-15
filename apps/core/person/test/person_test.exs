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

  describe "work contact details" do
    test "a namecard keeps email and phone on the affiliation, not the person", %{scope: scope} do
      input = %{full_name: "Vera", email: "vera@a.test", phone: "+601", title: "Sales"}
      assert {:ok, %{person: person, affiliation: a}} = Person.create_contact(scope, 74, input)
      assert {person.email, person.phone} == {nil, nil}
      assert {a.email, a.phone} == {"vera@a.test", "+601"}

      assert {:ok, %{entries: [%{id: id}]}} = Person.list(scope, search: "vera@a.test")
      assert id == person.id

      assert {:ok, _} = Person.unlink(scope, person.id, a.id)
      assert {:ok, b} = Person.link(scope, person.id, 73, %{email: "vera@b.test"})

      assert {:ok, %{email: nil, phone: nil, affiliations: [first, second]}} =
               Person.get(scope, person.id)

      assert {first.email, second.id, second.email} == {"vera@a.test", b.id, "vera@b.test"}
    end

    test "the namecard preview shows the contact once, on the affiliation", %{scope: scope} do
      input = %{"company_id" => 74, "full_name" => "Vera", "email" => "vera@a.test"}
      assert {:ok, %{changes: changes}} = Person.preview(scope, :contact, input)
      assert [_] = Enum.filter(changes, &(&1.field == "email"))
      assert {:ok, %{entries: []}} = Person.list(scope)
    end

    test "a bare person (no company) keeps its own contact details", %{scope: scope} do
      assert {:ok, person} =
               Person.create(scope, %{full_name: "Lena", email: "lena@lead.test", phone: "+602"})

      assert {person.email, person.phone} == {"lena@lead.test", "+602"}
      assert {:ok, %{entries: [%{id: id}]}} = Person.list(scope, search: "lena@lead.test")
      assert id == person.id
    end
  end

  describe "affiliation dates" do
    test "a namecard and a later link carry start and end dates, kept in history", %{
      scope: scope
    } do
      assert {:ok, %{person: person, affiliation: a}} =
               Person.create_contact(scope, 74, %{
                 full_name: "Vera",
                 title: "Sales",
                 started_on: "2024-02-01"
               })

      assert {a.started_on, a.ended_on} == {~D[2024-02-01], nil}

      assert {:ok, updated} =
               Person.update_affiliation(scope, person.id, a.id, %{ended_on: "2025-06-30"})

      assert updated.id == a.id
      assert {updated.started_on, updated.ended_on} == {~D[2024-02-01], ~D[2025-06-30]}

      assert {:ok, second} =
               Person.link(scope, person.id, 73, %{started_on: "2025-07-01", title: "Adviser"})

      assert second.started_on == ~D[2025-07-01]
      assert {:ok, %{affiliations: [first, later]}} = Person.get(scope, person.id)

      assert {first.ended_on, later.id, later.started_on} ==
               {~D[2025-06-30], second.id, ~D[2025-07-01]}
    end

    test "an end date before the start date is refused on every write", %{scope: scope} do
      assert {:error, %Ecto.Changeset{} = cs} =
               Person.create_contact(scope, 74, %{
                 full_name: "Vera",
                 started_on: "2025-01-02",
                 ended_on: "2025-01-01"
               })

      assert %{ended_on: [_], started_on: [_]} = Bilimbi.Base.Database.TestHelpers.errors_on(cs)
      {:ok, person} = Person.create(scope, %{full_name: "Una"})

      assert {:error, %Ecto.Changeset{}} =
               Person.link(scope, person.id, 74, %{
                 started_on: "2025-01-02",
                 ended_on: "2025-01-01"
               })

      {:ok, link} = Person.link(scope, person.id, 74, %{started_on: "2025-01-02"})

      assert {:error, %Ecto.Changeset{}} =
               Person.update_affiliation(scope, person.id, link.id, %{ended_on: "2025-01-01"})

      assert {:error, %Ecto.Changeset{}} =
               Person.preview(scope, :affiliation_update, %{
                 "person_id" => person.id,
                 "affiliation_id" => link.id,
                 "ended_on" => "2025-01-01"
               })
    end

    test "unlinking sets the end date and keeps history; an earlier end date is kept", %{
      scope: scope
    } do
      {:ok, person} = Person.create(scope, %{full_name: "Vera"})
      {:ok, open} = Person.link(scope, person.id, 74, %{started_on: "2020-01-01"})
      today = Date.utc_today()

      assert {:ok, %{ended_on: ^today, unlinked_at: %NaiveDateTime{}}} =
               Person.unlink(scope, person.id, open.id)

      {:ok, left} = Person.link(scope, person.id, 74, %{ended_on: "2021-05-05"})
      assert {:ok, %{ended_on: ~D[2021-05-05]}} = Person.unlink(scope, person.id, left.id)

      {:ok, planned} = Person.link(scope, person.id, 74, %{ended_on: "2999-01-01"})
      assert {:ok, %{ended_on: ^today}} = Person.unlink(scope, person.id, planned.id)
      assert {:ok, %{affiliations: rows}} = Person.get(scope, person.id)
      assert length(rows) == 3
    end

    test "previews show dates without mutating; unlink preview defers the clock", %{
      scope: scope
    } do
      assert {:ok, preview} =
               Person.preview(scope, :contact, %{
                 "company_id" => 74,
                 "full_name" => "Vera",
                 "started_on" => "2024-02-01"
               })

      assert Enum.any?(preview.changes, &(&1.field == "started_on" and &1.to == ~D[2024-02-01]))
      assert {:ok, %{entries: []}} = Person.list(scope)

      {:ok, %{person: person, affiliation: a}} =
        Person.create_contact(scope, 74, %{full_name: "Vera"})

      input = %{"person_id" => person.id, "affiliation_id" => a.id}
      assert {:ok, %{changes: changes}} = Person.preview(scope, :unlink, input)
      assert Enum.any?(changes, &(&1.field == "ended_on" and &1.to == "recorded at commit"))

      assert {:ok, %{affiliations: [%{unlinked_at: nil, ended_on: nil}]}} =
               Person.get(scope, person.id)
    end
  end
end
