defmodule Bilimbi.Core.Company.ExtendedTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company

  import Bilimbi.Core.Company.TestFixtures

  setup do
    create_company_identity_tables!()
    create_departments_table!()
    create_legal_entity_types_table!()
    create_external_access_tables!()

    insert_tenant!(%{id: 41, is_platform_operator: true})
    insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})

    insert_company!(%{
      id: 73,
      tenant_id: 41,
      name: "Bilimbi Industries",
      code: "bilimbi_industries"
    })

    insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Bilimbi Subsidiary",
      code: "bilimbi_subsidiary"
    })

    insert_company!(%{
      id: 75,
      tenant_id: 42,
      name: "Foreign Company",
      code: "foreign_company"
    })

    {:ok, scope_41} = Tenancy.scope(41)
    {:ok, scope_42} = Tenancy.scope(42)

    %{scope: scope_41, other_scope: scope_42}
  end

  describe "Legal Entity Types" do
    test "lists, creates, updates, toggles, and deletes legal entity types" do
      assert {:ok, []} = Company.list_legal_entity_types()

      assert {:ok, type} =
               Company.create_legal_entity_type(%{
                 code: "LLC",
                 name: "Limited Liability Company",
                 description: "US LLC structure",
                 is_active: true
               })

      assert type.code == "LLC"
      assert type.name == "Limited Liability Company"
      assert type.is_active == true

      assert {:ok, [listed]} = Company.list_legal_entity_types()
      assert listed.id == type.id

      assert {:ok, fetched} = Company.get_legal_entity_type(type.id)
      assert fetched.id == type.id

      assert {:ok, updated} =
               Company.update_legal_entity_type(type, %{
                 name: "Limited Liability Co"
               })

      assert updated.name == "Limited Liability Co"

      assert {:ok, toggled} = Company.toggle_legal_entity_type_active(type.id)
      assert toggled.is_active == false

      assert :ok = Company.delete_legal_entity_type(type.id)
      assert {:error, :not_found} = Company.get_legal_entity_type(type.id)
    end

    test "prevents duplicate codes for legal entity types" do
      assert {:ok, _} =
               Company.create_legal_entity_type(%{
                 code: "CORP",
                 name: "Corporation"
               })

      assert {:error, changeset} =
               Company.create_legal_entity_type(%{
                 code: "CORP",
                 name: "Duplicate Corp"
               })

      assert "has already been taken" in errors_on(changeset).code
    end

    test "refuses to delete legal entity type in use by a company" do
      {:ok, type} =
        Company.create_legal_entity_type(%{
          code: "HOLDING",
          name: "Holding Company"
        })

      Ecto.Adapters.SQL.query!(
        Bilimbi.Base.Repo,
        "UPDATE companies SET legal_entity_type_id = $1 WHERE id = 73",
        [type.id]
      )

      assert {:error, :in_use} = Company.delete_legal_entity_type(type.id)
    end
  end

  describe "Department Types" do
    test "lists, filters by category, creates, updates, and deletes department types" do
      assert {:ok, []} = Company.list_department_types()

      assert {:ok, eng} =
               Company.create_department_type(%{
                 code: "ENG",
                 name: "Engineering",
                 category: "operational",
                 description: "Software engineering",
                 is_active: true
               })

      assert {:ok, hr} =
               Company.create_department_type(%{
                 code: "HR",
                 name: "Human Resources",
                 category: "administrative",
                 is_active: true
               })

      assert {:ok, all} = Company.list_department_types()
      assert length(all) == 2

      assert {:ok, [only_eng]} = Company.list_department_types(category: "operational")
      assert only_eng.id == eng.id

      assert {:ok, [only_hr]} = Company.list_department_types(category: "administrative")
      assert only_hr.id == hr.id

      assert {:ok, updated} =
               Company.update_department_type(eng, %{
                 name: "Software Engineering"
               })

      assert updated.name == "Software Engineering"

      assert {:ok, toggled} = Company.toggle_department_type_active(eng.id)
      assert toggled.is_active == false

      assert :ok = Company.delete_department_type(eng.id)
      assert {:error, :not_found} = Company.get_department_type(eng.id)
    end

    test "prevents duplicate codes for department types" do
      assert {:ok, _} =
               Company.create_department_type(%{
                 code: "FIN",
                 name: "Finance",
                 category: "administrative"
               })

      assert {:error, changeset} =
               Company.create_department_type(%{
                 code: "FIN",
                 name: "Financials",
                 category: "administrative"
               })

      assert "has already been taken" in errors_on(changeset).code
    end

    test "validates category enum" do
      assert {:error, changeset} =
               Company.create_department_type(%{
                 code: "INVALID",
                 name: "Invalid Dept",
                 category: "unsupported_category"
               })

      assert "is invalid" in errors_on(changeset).category
    end
  end

  describe "Company Departments" do
    test "lists available types and manages company departments", %{
      scope: scope,
      other_scope: other_scope
    } do
      {:ok, eng} =
        Company.create_department_type(%{
          code: "ENG",
          name: "Engineering",
          category: "operational"
        })

      {:ok, hr} =
        Company.create_department_type(%{
          code: "HR",
          name: "Human Resources",
          category: "administrative"
        })

      assert {:ok, [t1, t2]} = Company.list_available_department_types(scope, 73)
      assert Enum.map([t1, t2], & &1.id) |> Enum.sort() == Enum.sort([eng.id, hr.id])

      assert {:ok, dept} =
               Company.create_department(scope, 73, %{
                 department_type_id: eng.id,
                 status: "active"
               })

      assert dept.company_id == 73
      assert dept.department_type_id == eng.id
      assert dept.status == "active"
      assert dept.type.name == "Engineering"

      assert {:ok, [available_now]} = Company.list_available_department_types(scope, 73)
      assert available_now.id == hr.id

      assert {:ok, [listed_dept]} = Company.list_departments(scope, 73)
      assert listed_dept.id == dept.id

      assert {:ok, suspended} =
               Company.update_department_status(scope, 73, dept.id, "suspended")

      assert suspended.status == "suspended"

      assert {:ok, deactivated} =
               Company.update_department_status(scope, 73, dept.id, "inactive")

      assert deactivated.status == "inactive"

      assert :ok = Company.delete_department(scope, 73, dept.id)
      assert {:ok, []} = Company.list_departments(scope, 73)

      # Cannot access from other tenant's scope
      assert {:error, :company_not_found} = Company.list_departments(other_scope, 73)

      assert {:error, :company_not_found} =
               Company.list_available_department_types(other_scope, 73)
    end

    test "refuses to delete department type in use by a company department", %{scope: scope} do
      {:ok, eng} =
        Company.create_department_type(%{
          code: "ENG",
          name: "Engineering",
          category: "operational"
        })

      {:ok, _dept} =
        Company.create_department(scope, 73, %{
          department_type_id: eng.id,
          status: "active"
        })

      assert {:error, :in_use} = Company.delete_department_type(eng.id)
    end
  end

  describe "Company Relationships" do
    test "creates, lists bidirectional, updates, and deletes relationships", %{
      scope: scope,
      other_scope: other_scope
    } do
      insert_relationship_type!(11)

      assert {:ok, active_types} = Company.list_active_relationship_types()
      assert length(active_types) == 1

      assert {:ok, available_co} = Company.list_available_related_companies(scope, 73)
      assert Enum.map(available_co, & &1.id) == [74]

      assert {:ok, rel} =
               Company.create_relationship(scope, 73, %{
                 related_company_id: 74,
                 relationship_type_id: 11,
                 effective_from: ~D[2026-01-01],
                 effective_to: ~D[2026-12-31]
               })

      assert rel.company_id == 73
      assert rel.related_company_id == 74

      # Outgoing from 73
      assert {:ok, [rel_item_73]} = Company.list_relationships(scope, 73)
      assert rel_item_73.direction == :outgoing
      assert rel_item_73.other_company.id == 74
      assert rel_item_73.type.name == "Customer"

      # Incoming to 74
      assert {:ok, [rel_item_74]} = Company.list_relationships(scope, 74)
      assert rel_item_74.direction == :incoming
      assert rel_item_74.other_company.id == 73

      # Update relationship
      assert {:ok, updated_rel} =
               Company.update_relationship(scope, 73, rel.id, %{
                 effective_to: ~D[2027-12-31]
               })

      assert updated_rel.effective_to == ~D[2027-12-31]

      # Delete relationship (soft-delete)
      assert :ok = Company.delete_relationship(scope, 73, rel.id)
      assert {:ok, []} = Company.list_relationships(scope, 73)

      # Cannot relate to company in other tenant
      assert {:error, :company_not_found} =
               Company.create_relationship(scope, 73, %{
                 related_company_id: 75,
                 relationship_type_id: 11
               })

      # Cannot relate to self
      assert {:error, changeset} =
               Company.create_relationship(scope, 73, %{
                 related_company_id: 73,
                 relationship_type_id: 11
               })

      assert "cannot create a relationship with itself" in errors_on(changeset).related_company_id

      # Cross tenant access fails
      assert {:error, :company_not_found} = Company.list_relationships(other_scope, 73)
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
