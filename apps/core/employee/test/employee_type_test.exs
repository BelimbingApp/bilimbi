defmodule Bilimbi.Core.Employee.EmployeeTypeTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee

  import Bilimbi.Core.Employee.TestFixtures

  setup do
    create_employee_tables!()

    CompanyFixtures.insert_tenant!(%{id: 51, name: "Tenant 1"})

    CompanyFixtures.insert_company!(%{
      id: 81,
      tenant_id: 51,
      name: "Company 1",
      code: "company_1"
    })

    CompanyFixtures.insert_tenant!(%{
      id: 52,
      name: "Tenant 2",
      is_platform_operator: false
    })

    CompanyFixtures.insert_company!(%{
      id: 82,
      tenant_id: 52,
      name: "Company 2",
      code: "company_2"
    })

    insert_department!(201, 81)
    insert_department!(202, 82)
    :ok = Employee.ensure_system_types()

    {:ok, scope_1} = Tenancy.scope(51)
    {:ok, scope_2} = Tenancy.scope(52)

    %{scope_1: scope_1, scope_2: scope_2}
  end

  describe "list_employee_types/2" do
    test "lists system types and company custom types ordered by is_system desc, label asc, code asc",
         %{scope_1: scope_1, scope_2: scope_2} do
      assert {:ok, _type_1} =
               Employee.create_employee_type(scope_1, 81, %{
                 code: "apprentice",
                 label: "Apprentice"
               })

      assert {:ok, _type_2} =
               Employee.create_employee_type(scope_1, 81, %{
                 code: "volunteer",
                 label: "Volunteer"
               })

      assert {:ok, types_1} = Employee.list_employee_types(scope_1, 81)
      assert length(types_1) == 7
      codes_1 = Enum.map(types_1, & &1.code)
      assert "full_time" in codes_1
      assert "agent" in codes_1
      assert "apprentice" in codes_1
      assert "volunteer" in codes_1

      # Company 2 sees system types but not Company 1's custom types
      assert {:ok, types_2} = Employee.list_employee_types(scope_2, 82)
      assert length(types_2) == 5
      codes_2 = Enum.map(types_2, & &1.code)
      assert "full_time" in codes_2
      assert "agent" in codes_2
      refute "apprentice" in codes_2
      refute "volunteer" in codes_2
    end

    test "refuses listing when company does not exist in scope", %{scope_1: scope_1} do
      assert {:error, :company_not_found} = Employee.list_employee_types(scope_1, 999)
      assert {:error, :company_not_found} = Employee.list_employee_types(scope_1, 82)
    end
  end

  describe "create_employee_type/3" do
    test "creates custom employee type and permits cross-company custom code collision", %{
      scope_1: scope_1,
      scope_2: scope_2
    } do
      assert {:ok, custom_1} =
               Employee.create_employee_type(scope_1, 81, %{
                 code: "seasonal",
                 label: "Seasonal Staff C1"
               })

      assert custom_1.code == "seasonal"
      assert custom_1.label == "Seasonal Staff C1"
      assert custom_1.company_id == 81
      assert custom_1.is_system == false

      # Company 2 creates same code 'seasonal' -> succeeds due to per-company partial unique index
      assert {:ok, custom_2} =
               Employee.create_employee_type(scope_2, 82, %{
                 code: "seasonal",
                 label: "Seasonal Staff C2"
               })

      assert custom_2.code == "seasonal"
      assert custom_2.label == "Seasonal Staff C2"
      assert custom_2.company_id == 82
    end

    test "rejects duplicate code within same company", %{scope_1: scope_1} do
      assert {:ok, _} =
               Employee.create_employee_type(scope_1, 81, %{
                 code: "probationary",
                 label: "Probationary"
               })

      assert {:error, changeset} =
               Employee.create_employee_type(scope_1, 81, %{
                 code: "probationary",
                 label: "Probationary Duplicate"
               })

      assert errors_on(changeset) == %{code: ["has already been taken"]}
    end

    test "rejects reserved system type codes", %{scope_1: scope_1} do
      for reserved <- ["full_time", "agent"] do
        assert {:error, changeset} =
                 Employee.create_employee_type(scope_1, 81, %{
                   code: reserved,
                   label: "Reserved Test"
                 })

        assert errors_on(changeset) == %{code: ["is reserved for a system employee type"]}
      end
    end
  end

  describe "update_employee_type/4" do
    test "updates label of company custom type", %{scope_1: scope_1} do
      assert {:ok, type} =
               Employee.create_employee_type(scope_1, 81, %{
                 code: "temp_hire",
                 label: "Temporary Hire"
               })

      assert {:ok, updated} =
               Employee.update_employee_type(scope_1, 81, type.id, %{
                 label: "Contract Worker"
               })

      assert updated.id == type.id
      assert updated.code == "temp_hire"
      assert updated.label == "Contract Worker"
    end

    test "rejects updating immutable code", %{scope_1: scope_1} do
      assert {:ok, type} =
               Employee.create_employee_type(scope_1, 81, %{
                 code: "shift_worker",
                 label: "Shift Worker"
               })

      # Passing code in attrs is ignored (only label is castable)
      assert {:ok, updated} =
               Employee.update_employee_type(scope_1, 81, type.id, %{
                 code: "changed_code",
                 label: "Shift Worker Modified"
               })

      assert updated.code == "shift_worker"
      assert updated.label == "Shift Worker Modified"
    end

    test "rejects updating system types", %{scope_1: scope_1} do
      assert {:ok, types} = Employee.list_employee_types(scope_1, 81)
      system_type = Enum.find(types, &(&1.code == "full_time"))

      assert {:error, :is_system} =
               Employee.update_employee_type(scope_1, 81, system_type.id, %{
                 label: "Changed Full Time"
               })
    end

    test "rejects updating custom type belonging to another company", %{
      scope_1: scope_1,
      scope_2: scope_2
    } do
      assert {:ok, type_1} =
               Employee.create_employee_type(scope_1, 81, %{
                 code: "c1_type",
                 label: "C1 Type"
               })

      assert {:error, :type_not_found} =
               Employee.update_employee_type(scope_2, 82, type_1.id, %{
                 label: "Hacked"
               })
    end

    test "rejects updating non-existent type", %{scope_1: scope_1} do
      assert {:error, :type_not_found} =
               Employee.update_employee_type(scope_1, 81, 999_999, %{
                 label: "Non existent"
               })
    end

    test "validates required label", %{scope_1: scope_1} do
      assert {:ok, type} =
               Employee.create_employee_type(scope_1, 81, %{
                 code: "apprentice",
                 label: "Apprentice"
               })

      assert {:error, changeset} =
               Employee.update_employee_type(scope_1, 81, type.id, %{label: ""})

      assert errors_on(changeset) == %{label: ["can't be blank"]}
    end
  end

  describe "delete_employee_type/3" do
    test "deletes unused custom employee type", %{scope_1: scope_1} do
      assert {:ok, type} =
               Employee.create_employee_type(scope_1, 81, %{
                 code: "freelance",
                 label: "Freelance"
               })

      assert :ok = Employee.delete_employee_type(scope_1, 81, type.id)

      assert {:ok, types} = Employee.list_employee_types(scope_1, 81)
      refute Enum.any?(types, &(&1.id == type.id))
    end

    test "refuses deleting system employee type", %{scope_1: scope_1} do
      assert {:ok, types} = Employee.list_employee_types(scope_1, 81)
      system_type = Enum.find(types, &(&1.code == "full_time"))

      assert {:error, :is_system} = Employee.delete_employee_type(scope_1, 81, system_type.id)
    end

    test "refuses deleting custom employee type in use by an employee", %{scope_1: scope_1} do
      assert {:ok, type} =
               Employee.create_employee_type(scope_1, 81, %{
                 code: "consultant",
                 label: "Consultant"
               })

      assert {:ok, _employee} =
               Employee.create_employee(scope_1, 81, %{
                 employee_number: "EMP-CONS-1",
                 full_name: "Jane Consultant",
                 department_id: 201,
                 employee_type: "consultant"
               })

      assert {:error, :in_use} = Employee.delete_employee_type(scope_1, 81, type.id)
    end

    test "refuses deleting custom type belonging to another company", %{
      scope_1: scope_1,
      scope_2: scope_2
    } do
      assert {:ok, type_1} =
               Employee.create_employee_type(scope_1, 81, %{
                 code: "c1_only",
                 label: "C1 Only"
               })

      assert {:error, :type_not_found} = Employee.delete_employee_type(scope_2, 82, type_1.id)
    end

    test "refuses deleting non-existent type", %{scope_1: scope_1} do
      assert {:error, :type_not_found} = Employee.delete_employee_type(scope_1, 81, 999_999)
    end
  end

  describe "database integrity and check constraint" do
    test "rejects company-less custom type (company_id IS NULL and is_system = false)" do
      assert_raise Postgrex.Error, ~r/employee_types_custom_company_check/, fn ->
        Ecto.Adapters.SQL.query!(
          Bilimbi.Base.Repo,
          """
          INSERT INTO employee_types (code, label, is_system, company_id)
          VALUES ('orphan_custom', 'Orphan Custom', false, NULL)
          """,
          []
        )
      end
    end

    test "rejects company-owned system type (company_id IS NOT NULL and is_system = true)" do
      assert_raise Postgrex.Error, ~r/employee_types_custom_company_check/, fn ->
        Ecto.Adapters.SQL.query!(
          Bilimbi.Base.Repo,
          """
          INSERT INTO employee_types (code, label, is_system, company_id)
          VALUES ('company_system', 'Company System', true, 81)
          """,
          []
        )
      end
    end
  end

  describe "scope enforcement" do
    test "requires valid %Scope{} on all employee type endpoints", %{scope_1: scope_1} do
      for not_a_scope <- [51, nil, "51", scope_1.tenant] do
        assert_raise FunctionClauseError, fn ->
          Employee.list_employee_types(opaque(not_a_scope), 81)
        end

        assert_raise FunctionClauseError, fn ->
          Employee.create_employee_type(opaque(not_a_scope), 81, %{code: "t", label: "T"})
        end

        assert_raise FunctionClauseError, fn ->
          Employee.update_employee_type(opaque(not_a_scope), 81, 1, %{label: "T"})
        end

        assert_raise FunctionClauseError, fn ->
          Employee.delete_employee_type(opaque(not_a_scope), 81, 1)
        end
      end
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp opaque(value), do: :erlang.element(1, {value})
end
