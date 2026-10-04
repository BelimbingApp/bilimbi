defmodule BilimbiWeb.CompanyDepartmentsLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.Department
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_legal_entity_types_table!()

    CompanyFixtures.insert_tenant!(%{id: 41, is_platform_operator: true})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})

    CompanyFixtures.insert_company!(%{
      id: 73,
      tenant_id: 41,
      name: "Bilimbi Industries",
      code: "bilimbi_industries"
    })

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 41,
      name: "Bilimbi Subsidiary",
      code: "bilimbi_subsidiary",
      parent_id: 73
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    UserFixtures.insert_user!(%{
      id: 96,
      company_id: 75,
      name: "Grace Hopper",
      email: "grace.hopper@example.com"
    })

    :ok
  end

  describe "Company Departments Live" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies/73/departments")
    end

    test "redirects without admin.company.view", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/73/departments")
    end

    test "manages company departments and status transitions", %{conn: conn} do
      grant_capabilities!(["admin.company.view", "admin.company.update"])

      {:ok, eng} =
        Bilimbi.Core.Company.create_department_type(scope!(), %{
          code: "ENG",
          name: "Engineering",
          category: "operational"
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/departments")

      assert has_element?(view, "h1", "Bilimbi Industries — Departments")
      assert has_element?(view, "#company-departments-empty")
      assert has_element?(view, "#company-departments-card[role='region']")
      assert has_element?(view, "#company-departments-heading", "Departments")

      assert has_element?(
               view,
               "a#departments-back[href='/companies/73'][title='Back to Bilimbi Industries']",
               "Back"
             )

      refute has_element?(view, "button#departments-back")

      # Add Department
      view |> element("#add-dept-btn") |> render_click()
      assert has_element?(view, "#department-modal")

      view
      |> form("#department-form", %{
        "department" => %{
          "department_type_id" => to_string(eng.id),
          "status" => "active"
        }
      })
      |> render_submit()

      refute has_element?(view, "#department-modal")
      assert has_element?(view, "#company-departments td", "Engineering")

      # Get department record
      dept = Bilimbi.Base.Repo.get_by!(Bilimbi.Core.Company.Department, company_id: 73)

      # Suspend
      view |> element("#suspend-dept-#{dept.id}") |> render_click()
      assert has_element?(view, "#company-departments span", "suspended")

      # Activate
      view |> element("#activate-dept-#{dept.id}") |> render_click()
      assert has_element?(view, "#company-departments span", "active")

      # Deactivate
      view |> element("#deactivate-dept-#{dept.id}") |> render_click()
      assert has_element?(view, "#company-departments span", "inactive")

      # Removing confirms through the shared dialog, which names the department
      # and says what happens to the employees assigned to it.
      refute has_element?(view, "#delete-dept-#{dept.id}[data-confirm]")
      view |> element("#delete-dept-#{dept.id}") |> render_click()

      assert_modal_dialog(
        view,
        "delete-dept-confirm",
        "The Engineering department will be removed from this company."
      )

      assert has_element?(view, "dialog#delete-dept-confirm[role='alertdialog']")

      assert has_element?(
               view,
               "#delete-dept-confirm-description",
               "Employees assigned to it keep their records but lose this department. This cannot be undone."
             )

      # Cancelling keeps the department.
      view |> element("#delete-dept-confirm-cancel", "Cancel") |> render_click()
      refute has_element?(view, "#delete-dept-confirm")
      refute has_element?(view, "#company-departments-empty")

      # Confirming removes it and reports the completed write as a success.
      view |> element("#delete-dept-#{dept.id}") |> render_click()

      assert has_element?(
               view,
               "#delete-dept-confirm-confirm[phx-disable-with='Removing…']",
               "Remove"
             )

      view |> element("#delete-dept-confirm-confirm") |> render_click()
      refute has_element?(view, "#delete-dept-confirm")
      assert has_element?(view, "#flash-success", "Department removed.")
      assert has_element?(view, "#company-departments-empty")
    end

    test "appoints, reassigns, and clears a department head through the employee directory", %{
      conn: conn
    } do
      grant_capabilities!(["admin.company.view", "admin.company.update"])
      {:ok, scope} = Tenancy.scope(41)
      :ok = Employee.ensure_system_types()

      {:ok, ada} =
        Employee.create_employee(scope, 73, %{
          employee_number: "EMP-201",
          full_name: "Ada Lovelace",
          employee_type: "full_time"
        })

      {:ok, grace} =
        Employee.create_employee(scope, 73, %{
          employee_number: "EMP-202",
          full_name: "Grace Hopper",
          employee_type: "full_time"
        })

      {:ok, sibling_employee} =
        Employee.create_employee(scope, 74, %{
          employee_number: "EMP-203",
          full_name: "Katherine Johnson",
          employee_type: "full_time"
        })

      {:ok, type} = Company.create_department_type(scope!(), %{code: "ENG", name: "Engineering"})

      {:ok, department} =
        Company.create_department(scope, 73, %{department_type_id: type.id, status: "active"})

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/departments")

      view |> element("#edit-dept-head-#{department.id}") |> render_click()

      assert has_element?(view, "#department-head-modal")
      assert has_element?(view, "#department-head-id option", "Ada Lovelace")
      assert has_element?(view, "#department-head-id option", "Grace Hopper")
      refute has_element?(view, "#department-head-id option", "Katherine Johnson")

      view
      |> form("#department-head-form", %{"department_head" => %{"head_id" => ada.id}})
      |> render_submit()

      assert Repo.get!(Department, department.id).head_id == ada.id
      assert has_element?(view, "#company-departments td", "Ada Lovelace")

      view |> element("#edit-dept-head-#{department.id}") |> render_click()

      view
      |> form("#department-head-form", %{"department_head" => %{"head_id" => grace.id}})
      |> render_submit()

      assert Repo.get!(Department, department.id).head_id == grace.id

      view |> element("#edit-dept-head-#{department.id}") |> render_click()

      render_submit(view, "save_head", %{
        "department_head" => %{"head_id" => sibling_employee.id}
      })

      assert has_element?(
               view,
               "#flash-error",
               "That employee is not eligible to lead this department."
             )

      assert Repo.get!(Department, department.id).head_id == grace.id

      view
      |> form("#department-head-form", %{"department_head" => %{"head_id" => ""}})
      |> render_submit()

      assert Repo.get!(Department, department.id).head_id == nil
      assert has_element?(view, "#company-departments td", "—")
    end

    test "reports a failed head write inside the open dialog, not behind it", %{conn: conn} do
      grant_capabilities!(["admin.company.view", "admin.company.update"])
      {:ok, scope} = Tenancy.scope(41)

      {:ok, type} = Company.create_department_type(scope!(), %{code: "ENG", name: "Engineering"})

      {:ok, department} =
        Company.create_department(scope, 73, %{department_type_id: type.id, status: "active"})

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/departments")

      view |> element("#edit-dept-head-#{department.id}") |> render_click()
      assert_modal_dialog(view, "department-head-modal", "Set Department Head")

      render_submit(view, "save_head", %{"department_head" => %{"head_id" => "999999"}})

      assert has_element?(view, "dialog#department-head-modal")

      assert has_element?(
               view,
               "dialog#department-head-modal #department-head-modal-flash-error",
               "That employee is not eligible to lead this department."
             )
    end

    test "ignores a forged department head while creating a department", %{conn: conn} do
      grant_capabilities!(["admin.company.view", "admin.company.update"])
      {:ok, scope} = Tenancy.scope(41)
      :ok = Employee.ensure_system_types()

      {:ok, sibling_employee} =
        Employee.create_employee(scope, 74, %{
          employee_number: "EMP-204",
          full_name: "Katherine Johnson",
          employee_type: "full_time"
        })

      {:ok, type} = Company.create_department_type(scope!(), %{code: "ENG", name: "Engineering"})

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/departments")

      render_submit(view, "save", %{
        "department" => %{
          "department_type_id" => to_string(type.id),
          "head_id" => to_string(sibling_employee.id),
          "status" => "active"
        }
      })

      department = Repo.get_by!(Department, company_id: 73)
      assert department.head_id == nil
    end

    test "re-authorizes a department-head write event after the capability is revoked", %{
      conn: conn
    } do
      grant_capabilities!(["admin.company.view", "admin.company.update"])
      {:ok, scope} = Tenancy.scope(41)
      :ok = Employee.ensure_system_types()

      {:ok, employee} =
        Employee.create_employee(scope, 73, %{
          employee_number: "EMP-204",
          full_name: "Margaret Hamilton",
          employee_type: "full_time"
        })

      {:ok, type} = Company.create_department_type(scope!(), %{code: "OPS", name: "Operations"})

      {:ok, department} =
        Company.create_department(scope, 73, %{department_type_id: type.id, status: "active"})

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/departments")

      {:ok, :stored} =
        Authz.put_principal_capability(
          scope,
          73,
          :user,
          91,
          "admin.company.update",
          false
        )

      render_click(view, "edit_head", %{"id" => to_string(department.id)})

      render_submit(view, "save_head", %{
        "department_head" => %{"head_id" => to_string(employee.id)}
      })

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      assert Repo.get!(Department, department.id).head_id == nil
    end

    test "hides write controls and rejects direct write events without update capability", %{
      conn: conn
    } do
      {:ok, type} =
        Company.create_department_type(scope!(), %{
          code: "ENG",
          name: "Engineering",
          category: "operational"
        })

      {:ok, scope} = Tenancy.scope(41)

      {:ok, department} =
        Company.create_department(scope, 73, %{
          "department_type_id" => to_string(type.id),
          "status" => "active"
        })

      grant_capabilities!(["admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/departments")

      refute has_element?(view, "#add-dept-btn")
      refute has_element?(view, "#suspend-dept-#{department.id}")
      refute has_element?(view, "#deactivate-dept-#{department.id}")
      refute has_element?(view, "#delete-dept-#{department.id}")
      refute has_element?(view, "#edit-dept-head-#{department.id}")

      render_click(view, "update_status", %{
        "id" => to_string(department.id),
        "status" => "suspended"
      })

      render_click(view, "delete", %{"id" => to_string(department.id)})

      render_click(view, "edit_head", %{"id" => to_string(department.id)})

      render_submit(view, "save", %{
        "department" => %{
          "department_type_id" => to_string(type.id),
          "status" => "inactive"
        }
      })

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      assert Repo.get!(Department, department.id).status == "active"
      assert Repo.aggregate(Department, :count) == 1
    end
  end

  defp scope! do
    {:ok, scope} = Tenancy.scope(41)
    scope
  end
end
