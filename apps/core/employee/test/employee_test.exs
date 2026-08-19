defmodule Bilimbi.Core.EmployeeTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.Summary

  import Bilimbi.Core.Employee.TestFixtures

  setup do
    create_employee_tables!()

    CompanyFixtures.insert_tenant!(%{id: 41, name: "Tenant A"})

    CompanyFixtures.insert_company!(%{
      id: 73,
      tenant_id: 41,
      name: "Company A",
      code: "company_a"
    })

    CompanyFixtures.insert_tenant!(%{
      id: 42,
      name: "Tenant B",
      is_platform_operator: false
    })

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 42,
      name: "Company B",
      code: "company_b"
    })

    insert_department!(101, 73)
    insert_department!(102, 74)
    :ok = Employee.ensure_system_types()

    {:ok, owner} = Tenancy.scope(41)
    {:ok, other} = Tenancy.scope(42)

    %{owner: owner, other: other}
  end

  test "creates, lists, and resolves employees inside an explicit tenant and company", %{
    owner: owner,
    other: other
  } do
    assert {:ok, employee} =
             Employee.create_employee(owner, 73, %{
               employee_number: "EMP-001",
               full_name: "John Richard Doe",
               short_name: "John",
               department_id: 101,
               email: "john@example.test",
               employment_start: ~D[2026-01-15]
             })

    assert employee.company_id == 73
    assert employee.employee_type == "full_time"
    assert employee.status == "active"
    assert Summary.display_name(employee) == "John"

    assert {:ok, [listed]} = Employee.list_employees(owner, 73)
    assert listed.id == employee.id
    assert {:ok, fetched} = Employee.get_employee(owner, 73, employee.id)
    assert fetched.employee_number == "EMP-001"

    assert {:ok, scope_fetched} = Employee.get_employee(owner, employee.id)
    assert scope_fetched.id == employee.id

    assert {:error, :company_not_found} = Employee.get_employee(other, 73, employee.id)
    assert {:error, :employee_not_found} = Employee.get_employee(other, employee.id)
    assert {:error, :employee_not_found} = Employee.get_employee(owner, 73, employee.id + 1)
  end

  test "returns a bounded administration page with source search, filters, and stable order", %{
    owner: owner
  } do
    for {number, name, type, status, attrs} <- [
          {"EMP-SEARCH-NAME", "Alpha Match", "full_time", "active", %{}},
          {"EMP-SEARCH-SHORT", "Bravo", "full_time", "active", %{short_name: "Alpha Alias"}},
          {"ALPHA-NUMBER", "Charlie", "full_time", "active", %{}},
          {"EMP-SEARCH-EMAIL", "Delta", "agent", "inactive", %{email: "alpha@example.test"}},
          {"EMP-SEARCH-DESIGNATION", "Echo", "agent", "pending", %{designation: "Alpha Lead"}},
          {"EMP-SEARCH-JOB", "Foxtrot", "full_time", "terminated",
           %{job_description: "alpha specialist"}},
          {"EMP-OTHER", "Zulu", "full_time", "active", %{}}
        ] do
      assert {:ok, _employee} =
               Employee.create_employee(
                 owner,
                 73,
                 Map.merge(attrs, %{
                   employee_number: number,
                   full_name: name,
                   employee_type: type,
                   status: status
                 })
               )
    end

    assert {:ok, page} = Employee.list_administration_page(owner, 73, search: "alpha")
    assert page.total_entries == 6
    assert page.total_pages == 1
    refute page.has_prev?
    refute page.has_next?

    assert Enum.map(page.entries, & &1.full_name) == [
             "Alpha Match",
             "Bravo",
             "Charlie",
             "Delta",
             "Echo",
             "Foxtrot"
           ]

    assert {:ok, agents} = Employee.list_administration_page(owner, 73, type_filter: :agent)
    assert Enum.map(agents.entries, & &1.full_name) == ["Delta", "Echo"]

    assert {:ok, humans} = Employee.list_administration_page(owner, 73, type_filter: :human)
    refute Enum.any?(humans.entries, &(&1.employee_type == "agent"))

    assert {:ok, status_desc} =
             Employee.list_administration_page(owner, 73, sort_by: :status, sort_dir: :desc)

    assert Enum.map(status_desc.entries, & &1.status) ==
             ["terminated", "pending", "inactive", "active", "active", "active", "active"]

    assert {:ok, full_name_desc} =
             Employee.list_administration_page(owner, 73, sort_by: :full_name, sort_dir: :desc)

    assert Enum.map(full_name_desc.entries, & &1.full_name) == [
             "Zulu",
             "Foxtrot",
             "Echo",
             "Delta",
             "Charlie",
             "Bravo",
             "Alpha Match"
           ]

    assert {:ok, status_asc} =
             Employee.list_administration_page(owner, 73, sort_by: :status, sort_dir: :asc)

    assert Enum.map(status_asc.entries, & &1.status) ==
             ["active", "active", "active", "active", "inactive", "pending", "terminated"]

    assert {:ok, type_desc} =
             Employee.list_administration_page(owner, 73,
               sort_by: :employee_type_label,
               sort_dir: :desc
             )

    assert Enum.map(type_desc.entries, & &1.employee_type) ==
             ["full_time", "full_time", "full_time", "full_time", "full_time", "agent", "agent"]

    assert Enum.map(type_desc.entries, & &1.employee_type_label) ==
             ["Full Time", "Full Time", "Full Time", "Full Time", "Full Time", "Agent", "Agent"]

    assert {:ok, type_asc} =
             Employee.list_administration_page(owner, 73,
               sort_by: :employee_type_label,
               sort_dir: :asc
             )

    assert Enum.map(type_asc.entries, & &1.employee_type) ==
             ["agent", "agent", "full_time", "full_time", "full_time", "full_time", "full_time"]
  end

  test "escapes literal LIKE wildcard input and keeps administration entries narrow", %{
    owner: owner
  } do
    assert {:ok, literal} =
             Employee.create_employee(owner, 73, %{
               employee_number: "EMP-100%_LITERAL",
               full_name: "Literal",
               job_description: "contains % and _"
             })

    assert {:ok, _broad} =
             Employee.create_employee(owner, 73, %{
               employee_number: "EMP-100xxLITERAL",
               full_name: "Broad Match"
             })

    assert {:ok, page} = Employee.list_administration_page(owner, 73, search: "100%_LITERAL")
    assert [entry] = page.entries
    assert page.page_size == 25
    assert entry.id == literal.id
    refute Map.has_key?(entry, :metadata)
    refute Map.has_key?(entry, :company_id)

    assert {:ok, slash_literal} =
             Employee.create_employee(owner, 73, %{
               employee_number: "EMP-SLASH",
               full_name: "Literal \\ path"
             })

    assert {:ok, _not_slash_literal} =
             Employee.create_employee(owner, 73, %{
               employee_number: "EMP-NO-SLASH",
               full_name: "Literal x path"
             })

    assert {:ok, slash_page} = Employee.list_administration_page(owner, 73, search: "\\")
    assert [slash_entry] = slash_page.entries
    assert slash_entry.id == slash_literal.id
  end

  test "administration pages reject invalid options and invalid company values", %{owner: owner} do
    for options <- [
          %{page: 1},
          [{:page, 1}, "bad"],
          [unknown: :value],
          [page: 0],
          [page: "1"],
          [page_size: 0],
          [page_size: 301],
          [search: :not_a_string],
          [type_filter: "agent"],
          [sort_by: "full_name"],
          [sort_by: :company_name],
          [sort_dir: "asc"],
          [page: 1, page: 2]
        ] do
      assert {:error, :invalid_options} = Employee.list_administration_page(owner, 73, options)
    end

    assert {:error, :company_not_found} = Employee.list_administration_page(owner, 0)
    assert {:error, :company_not_found} = Employee.list_administration_page(owner, 999)
    assert {:ok, page_300} = Employee.list_administration_page(owner, 73, page_size: 300)
    assert page_300.page_size == 300
  end

  test "administration pages prove a live company before querying its employees", %{
    owner: owner,
    other: other
  } do
    assert {:ok, _} =
             Employee.create_employee(other, 74, %{
               employee_number: "OTHER-ADMIN",
               full_name: "Other"
             })

    assert {:error, :company_not_found} = Employee.list_administration_page(owner, 74)

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      "UPDATE companies SET deleted_at = '2026-08-12 12:00:00' WHERE id = 73",
      []
    )

    assert {:error, :company_not_found} = Employee.list_administration_page(owner, 73)
  end

  test "administration pages paginate deterministically with id descending ties", %{owner: owner} do
    for number <- 1..4 do
      assert {:ok, _} =
               Employee.create_employee(owner, 73, %{
                 employee_number: "TIE-#{number}",
                 full_name: "Same Name"
               })
    end

    assert {:ok, first} = Employee.list_administration_page(owner, 73, page: 1, page_size: 2)
    assert {:ok, second} = Employee.list_administration_page(owner, 73, page: 2, page_size: 2)
    assert first.total_entries == 4
    assert first.total_pages == 2
    assert first.has_next?
    refute first.has_prev?
    assert second.has_prev?
    refute second.has_next?
    assert Enum.map(first.entries, & &1.id) == [4, 3]
    assert Enum.map(second.entries, & &1.id) == [2, 1]

    for {sort_by, sort_dir} <- [
          {:full_name, :asc},
          {:full_name, :desc},
          {:employee_type_label, :asc},
          {:employee_type_label, :desc},
          {:status, :asc},
          {:status, :desc}
        ] do
      assert {:ok, ordered} =
               Employee.list_administration_page(owner, 73,
                 page_size: 4,
                 sort_by: sort_by,
                 sort_dir: sort_dir
               )

      assert Enum.map(ordered.entries, & &1.id) == [4, 3, 2, 1]
    end

    assert {:ok, past_end} =
             Employee.list_administration_page(owner, 73, page: 3, page_size: 2)

    assert past_end.entries == []
    assert past_end.total_entries == 4
    assert past_end.total_pages == 2
    assert past_end.has_prev?
    refute past_end.has_next?

    assert {:ok, empty} =
             Employee.list_administration_page(owner, 73, search: "missing", page: 3)

    assert empty.entries == []
    assert empty.total_entries == 0
    assert empty.total_pages == 0
    assert empty.has_prev?
    refute empty.has_next?
  end

  test "scope-wide lookup excludes employees whose owning company is deleted", %{owner: owner} do
    assert {:ok, employee} =
             Employee.create_employee(owner, 73, %{
               employee_number: "EMP-ARCHIVED",
               full_name: "Archived Company Employee"
             })

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      "UPDATE companies SET deleted_at = '2026-08-12 12:00:00' WHERE id = 73",
      []
    )

    assert {:error, :employee_not_found} = Employee.get_employee(owner, employee.id)
  end

  test "rejects cross-company departments, supervisors, and employee types", %{
    owner: owner,
    other: other
  } do
    assert {:ok, other_company_employee} =
             Employee.create_employee(other, 74, %{
               employee_number: "OTHER-001",
               full_name: "Other Company Employee"
             })

    assert {:ok, _type} =
             Employee.create_employee_type(other, 74, %{code: "seasonal", label: "Seasonal"})

    assert {:error, changeset} =
             Employee.create_employee(owner, 73, %{
               employee_number: "EMP-002",
               full_name: "Invalid References",
               department_id: 102,
               supervisor_id: other_company_employee.id,
               employee_type: "seasonal"
             })

    assert errors_on(changeset) == %{
             department_id: ["does not belong to the company"],
             employee_type: ["is not available to the company"],
             supervisor_id: ["does not belong to the company"]
           }
  end

  test "validates unique numbers, employment periods, and self-supervision", %{owner: owner} do
    assert {:ok, employee} =
             Employee.create_employee(owner, 73, %{
               employee_number: "EMP-003",
               full_name: "Jane Smith"
             })

    assert {:error, duplicate} =
             Employee.create_employee(owner, 73, %{
               employee_number: "EMP-003",
               full_name: "Duplicate"
             })

    assert errors_on(duplicate) == %{employee_number: ["has already been taken"]}

    assert {:error, invalid_update} =
             Employee.update_employee(owner, 73, employee.id, %{
               supervisor_id: employee.id,
               employment_start: ~D[2026-06-01],
               employment_end: ~D[2026-05-31]
             })

    assert errors_on(invalid_update) == %{
             employment_end: ["must be on or after employment start"],
             supervisor_id: ["cannot reference the employee itself"]
           }
  end

  test "bootstraps global system types and isolates custom types by company", %{
    owner: owner,
    other: other
  } do
    assert {:ok, system_types} = Employee.list_employee_types(owner, 73)

    assert Enum.map(system_types, & &1.code) |> Enum.sort() ==
             ~w(agent contractor full_time intern part_time)

    assert {:ok, custom} =
             Employee.create_employee_type(owner, 73, %{code: "seasonal", label: "Seasonal"})

    refute custom.is_system
    assert custom.company_id == 73

    assert {:ok, company_a_types} = Employee.list_employee_types(owner, 73)
    assert "seasonal" in Enum.map(company_a_types, & &1.code)

    assert {:ok, company_b_types} = Employee.list_employee_types(other, 74)
    refute "seasonal" in Enum.map(company_b_types, & &1.code)
  end

  test "provisions the platform orchestrator by durable company-scoped identity", %{owner: owner} do
    assert {:ok, ordinary_employee} =
             Employee.create_employee(owner, 73, %{
               employee_number: "EMP-BEFORE-SYSTEM",
               full_name: "Existing Employee"
             })

    assert {:error, :not_provisioned} = Employee.platform_orchestrator()

    CompanyFixtures.assign_primary_company!(41, 73)

    assert {:ok, orchestrator, :created} = Employee.ensure_platform_orchestrator()
    assert orchestrator.id != ordinary_employee.id
    assert orchestrator.employee_number == "SYS-001"
    assert orchestrator.employee_type == "agent"
    assert orchestrator.employment_start == Date.utc_today()

    assert {:ok, same_orchestrator, :existing} = Employee.ensure_platform_orchestrator()
    assert same_orchestrator.id == orchestrator.id
    assert {:ok, resolved} = Employee.platform_orchestrator()
    assert resolved.id == orchestrator.id
  end

  test "protects the platform orchestrator identity through the public API", %{owner: owner} do
    CompanyFixtures.assign_primary_company!(41, 73)
    assert {:ok, orchestrator, :created} = Employee.ensure_platform_orchestrator()

    assert {:error, reserved} =
             Employee.create_employee(owner, 73, %{
               employee_number: "SYS-001",
               full_name: "Impostor",
               employee_type: "agent"
             })

    assert errors_on(reserved) == %{
             employee_number: ["is reserved for the platform orchestrator"]
           }

    assert {:error, protected} =
             Employee.update_employee(owner, 73, orchestrator.id, %{
               employee_number: "SYS-002",
               employee_type: "full_time",
               designation: "Updated designation"
             })

    assert errors_on(protected) == %{
             employee_number: ["cannot change the platform orchestrator identity"],
             employee_type: ["cannot change the platform orchestrator identity"]
           }

    assert {:ok, updated} =
             Employee.update_employee(owner, 73, orchestrator.id, %{
               designation: "Updated designation"
             })

    assert updated.designation == "Updated designation"
    assert updated.employee_number == "SYS-001"
    assert updated.employee_type == "agent"

    assert {:error, :invariant_violation} =
             Employee.delete_employee(owner, 73, orchestrator.id)

    assert {:ok, still_there} = Employee.get_employee(owner, 73, orchestrator.id)
    assert still_there.id == orchestrator.id

    assert {:ok, ordinary} =
             Employee.create_employee(owner, 73, %{
               employee_number: "EMP-DELETE",
               full_name: "Ordinary Employee"
             })

    assert :ok = Employee.delete_employee(owner, 73, ordinary.id)
    assert {:error, :employee_not_found} = Employee.get_employee(owner, 73, ordinary.id)
  end

  test "refuses a conflicting SYS-001 row instead of adopting it" do
    CompanyFixtures.assign_primary_company!(41, 73)
    insert_raw_employee!(73, "SYS-001", "full_time", "Conflicting Employee")

    assert {:error, :invariant_violation} = Employee.ensure_platform_orchestrator()
    assert {:error, :invariant_violation} = Employee.platform_orchestrator()
  end

  test "fails closed when primary-company transfer leaves the orchestrator behind", %{
    owner: owner
  } do
    CompanyFixtures.assign_primary_company!(41, 73)
    assert {:ok, orchestrator, :created} = Employee.ensure_platform_orchestrator()

    CompanyFixtures.insert_company!(%{id: 75, tenant_id: 41, code: "successor_company"})
    assert {:ok, :transferred} = Company.transfer_primary_company(owner, 75)

    assert {:error, :invariant_violation} = Employee.platform_orchestrator()
    assert {:error, :invariant_violation} = Employee.ensure_platform_orchestrator()

    assert {:ok, stranded} = Employee.get_employee(owner, 73, orchestrator.id)
    assert stranded.employee_number == "SYS-001"
  end

  test "refuses to convert an adopted custom type into a reserved system type", %{owner: owner} do
    Ecto.Adapters.SQL.query!(Bilimbi.Base.Repo, "DELETE FROM employee_types", [])
    insert_raw_employee_type!("agent", "Custom Agent", false, 73)

    assert {:error, :invariant_violation} = Employee.ensure_system_types()

    assert {:error, changeset} =
             Employee.create_employee_type(owner, 73, %{
               code: "full_time",
               label: "Full Time Custom"
             })

    assert errors_on(changeset) == %{code: ["is reserved for a system employee type"]}
  end

  test "publishes the canonical polymorphic identity without exposing its schema" do
    assert Employee.addressable_identity() == "App\\Core\\Employee\\Models\\Employee"
  end

  test "cannot be called without a scope", %{owner: owner} do
    for not_a_scope <- [41, nil, owner.tenant] do
      assert_raise FunctionClauseError, fn ->
        Employee.list_employees(opaque(not_a_scope), 73)
      end

      assert_raise FunctionClauseError, fn ->
        Employee.list_administration_page(opaque(not_a_scope), 73)
      end

      assert_raise FunctionClauseError, fn ->
        Employee.get_employee(opaque(not_a_scope), 73, 1)
      end

      assert_raise FunctionClauseError, fn ->
        Employee.get_employee(opaque(not_a_scope), 1)
      end

      assert_raise FunctionClauseError, fn ->
        Employee.create_employee(opaque(not_a_scope), 73, %{
          employee_number: "EMP-X",
          full_name: "Unscoped"
        })
      end
    end
  end

  defp insert_raw_employee!(company_id, employee_number, employee_type, full_name) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      """
      INSERT INTO employees (
        company_id, employee_number, full_name, employee_type, status, created_at, updated_at
      ) VALUES ($1, $2, $3, $4, 'active', $5, $5)
      """,
      [company_id, employee_number, full_name, employee_type, now]
    )
  end

  defp insert_raw_employee_type!(code, label, is_system, company_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      """
      INSERT INTO employee_types (code, label, is_system, company_id, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $5)
      """,
      [code, label, is_system, company_id, now]
    )
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
