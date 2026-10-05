defmodule BilimbiWeb.DepartmentTypesLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.DepartmentType
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_legal_entity_types_table!()

    CompanyFixtures.insert_tenant!(%{id: 41, is_platform_operator: true})

    CompanyFixtures.insert_company!(%{
      id: 73,
      tenant_id: 41,
      name: "Bilimbi Industries",
      code: "bilimbi_industries"
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    :ok
  end

  describe "Department Types Live" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies/department-types")
    end

    test "redirects without admin.company.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/department-types")
    end

    test "creates, filters, edits, toggles, and deletes department types", %{conn: conn} do
      grant_capabilities!([
        "admin.company.list",
        "admin.company.create",
        "admin.company.update",
        "admin.company.delete"
      ])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/department-types")

      assert has_element?(view, "h1", "Department Types")
      assert has_element?(view, "#nav-admin-company-department-type[aria-current='page']")

      assert has_element?(
               view,
               "a#department-types-back[href='/companies'][title='Back to companies']",
               "Back"
             )

      refute has_element?(view, "button#department-types-back")

      # Create Operational Type
      view |> element("#new-department-type-btn") |> render_click()
      assert has_element?(view, "#department-type-modal")

      view
      |> form("#department-type-form", %{
        "department_type" => %{
          "code" => "ENG",
          "name" => "Engineering",
          "category" => "operational",
          "description" => "Software and hardware engineering"
        }
      })
      |> render_submit()

      assert has_element?(view, "#department-types td", "Engineering")

      # Create Administrative Type
      view |> element("#new-department-type-btn") |> render_click()

      view
      |> form("#department-type-form", %{
        "department_type" => %{
          "code" => "HR",
          "name" => "Human Resources",
          "category" => "administrative"
        }
      })
      |> render_submit()

      assert has_element?(view, "#department-types td", "Human Resources")

      # Filter by category
      view |> element("button", "Administrative") |> render_click()
      assert has_element?(view, "#department-types td", "Human Resources")
      refute has_element?(view, "#department-types td", "Engineering")

      view |> element("button", "All") |> render_click()
      assert has_element?(view, "#department-types td", "Engineering")
      assert has_element?(view, "#department-types td", "Human Resources")

      # Edit
      eng = Bilimbi.Base.Repo.get_by!(Bilimbi.Core.Company.DepartmentType, code: "ENG")
      view |> element("#edit-dept-type-#{eng.id}") |> render_click()

      view
      |> form("#department-type-form", %{
        "department_type" => %{
          "name" => "Software Engineering"
        }
      })
      |> render_submit()

      assert has_element?(view, "#department-types td", "Software Engineering")

      # Delete HR through the shared confirmation: cancel keeps it, confirm
      # removes it and reports the completed write as a success.
      hr = Bilimbi.Base.Repo.get_by!(Bilimbi.Core.Company.DepartmentType, code: "HR")
      refute has_element?(view, "#delete-dept-type-#{hr.id}[data-confirm]")
      view |> element("#delete-dept-type-#{hr.id}") |> render_click()

      assert_modal_dialog(
        view,
        "delete-dept-type-confirm",
        "Department type “Human Resources” will be deleted."
      )

      assert has_element?(
               view,
               "#delete-dept-type-confirm-description",
               "It can no longer be chosen for a department. This cannot be undone."
             )

      view |> element("#delete-dept-type-confirm-cancel", "Cancel") |> render_click()
      refute has_element?(view, "#delete-dept-type-confirm")
      assert has_element?(view, "#department-types td", "Human Resources")

      view |> element("#delete-dept-type-#{hr.id}") |> render_click()
      view |> element("#delete-dept-type-confirm-confirm", "Delete") |> render_click()
      refute has_element?(view, "#delete-dept-type-confirm")
      assert has_element?(view, "#flash-success", "Department type deleted.")
      refute has_element?(view, "#department-types td", "Human Resources")
      refute Repo.get(DepartmentType, hr.id)
    end

    test "hides write controls and rejects direct write events without write capabilities", %{
      conn: conn
    } do
      {:ok, type} =
        Company.create_department_type(scope!(), %{
          code: "ENG",
          name: "Engineering",
          category: "operational",
          is_active: true
        })

      grant_capabilities!(["admin.company.list"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/department-types")

      refute has_element?(view, "#new-department-type-btn")
      refute has_element?(view, "#toggle-dept-type-#{type.id}")
      refute has_element?(view, "#edit-dept-type-#{type.id}")
      refute has_element?(view, "#delete-dept-type-#{type.id}")

      render_click(view, "toggle_active", %{"id" => to_string(type.id)})
      render_click(view, "delete", %{"id" => to_string(type.id)})

      render_submit(view, "save", %{
        "department_type" => %{
          "code" => "NEW",
          "name" => "Unauthorized",
          "category" => "operational"
        }
      })

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      assert Repo.get!(DepartmentType, type.id).is_active
      refute Repo.get_by(DepartmentType, code: "NEW")
    end
  end

  defp scope! do
    {:ok, scope} = Tenancy.scope(41)
    scope
  end
end
