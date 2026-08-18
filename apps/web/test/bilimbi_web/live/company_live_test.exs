defmodule BilimbiWeb.CompanyLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_legal_entity_types_table!()
    CompanyFixtures.create_external_access_tables!()

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
      code: "bilimbi_subsidiary"
    })

    CompanyFixtures.insert_company!(%{
      id: 75,
      tenant_id: 42,
      name: "Elsewhere",
      code: "elsewhere"
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  describe "Index" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies")
    end

    test "redirects away when the actor lacks admin.company.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies")
    end

    test "lists only the current tenant's companies", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies")

      assert has_element?(view, "#companies td", "Bilimbi Industries")
      refute has_element?(view, "#companies td", "Elsewhere")
      assert has_element?(view, "#nav-admin-company[aria-current='page']")
      assert has_element?(view, "#nav-branch-admin[data-nav-default-expanded='true']")
      assert has_element?(view, "#nav-toggle-admin[aria-expanded='true']")
      assert has_element?(view, "#nav-children-admin:not([hidden])")
    end
  end

  describe "Show" do
    test "redirects away when the actor lacks admin.company.view", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/73")
    end

    test "renders the company with its users and back button", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73")

      assert has_element?(view, "h1", "Bilimbi Industries")
      assert has_element?(view, "#company-back[href='/companies']", "Back to companies")
      assert has_element?(view, "#company-users-table td", "Ada Lovelace")

      assert has_element?(
               view,
               "#company-employees-table-empty",
               "No employees found for this company."
             )
    end

    test "redirects away for another tenant's company", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      assert {:error, {:live_redirect, %{to: "/companies"}}} =
               conn |> log_in_as() |> live(~p"/companies/75")
    end

    test "redirects away for a missing company", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.view"])

      assert {:error, {:live_redirect, %{to: "/companies"}}} =
               conn |> log_in_as() |> live(~p"/companies/9999")
    end
  end

  describe "Legal Entity Types Live" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies/legal-entity-types")
    end

    # Belimbing gates both type index screens on `admin.company.list`, not
    # `.view` (`app/Core/Company/Routes/web.php:25-30`), and that matches how
    # this app already splits the two: `/companies` is `.list`, `/companies/:id`
    # is `.view`. These are index screens.
    test "redirects without admin.company.list", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/legal-entity-types")
    end

    test "creates, validates, edits, toggles, and deletes legal entity types", %{conn: conn} do
      grant_capabilities!(["admin.company.list"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/legal-entity-types")

      assert has_element?(view, "h1", "Legal Entity Types")
      assert has_element?(view, "#legal-entity-types-empty", "No legal entity types defined yet.")

      # Open new modal
      view |> element("#new-legal-entity-type-btn") |> render_click()
      assert has_element?(view, "#legal-entity-type-modal")

      # Validate
      view
      |> form("#legal-entity-type-form", %{
        "legal_entity_type" => %{"code" => "LLC", "name" => ""}
      })
      |> render_change()

      assert has_element?(view, "#legal-entity-type-name + p", "can't be blank")

      # Save
      view
      |> form("#legal-entity-type-form", %{
        "legal_entity_type" => %{
          "code" => "LLC",
          "name" => "Limited Liability Company",
          "description" => "Standard LLC"
        }
      })
      |> render_submit()

      refute has_element?(view, "#legal-entity-type-modal")
      assert has_element?(view, "#legal-entity-types td", "Limited Liability Company")
      assert has_element?(view, "#legal-entity-types code", "LLC")

      # Edit
      type = Bilimbi.Base.Repo.get_by!(Bilimbi.Core.Company.LegalEntityType, code: "LLC")
      view |> element("#edit-type-#{type.id}") |> render_click()
      assert has_element?(view, "#legal-entity-type-modal")

      view
      |> form("#legal-entity-type-form", %{
        "legal_entity_type" => %{
          "name" => "Limited Liability Corp"
        }
      })
      |> render_submit()

      assert has_element?(view, "#legal-entity-types td", "Limited Liability Corp")

      # Toggle active
      view |> element("#toggle-type-#{type.id}") |> render_click()
      assert has_element?(view, "#legal-entity-types span", "inactive")

      view |> element("#toggle-type-#{type.id}") |> render_click()
      assert has_element?(view, "#legal-entity-types span", "active")

      # Delete
      view |> element("#delete-type-#{type.id}") |> render_click()
      assert has_element?(view, "#legal-entity-types-empty", "No legal entity types defined yet.")
    end
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
      grant_capabilities!(["admin.company.list"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/department-types")

      assert has_element?(view, "h1", "Department Types")

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

      # Delete HR
      hr = Bilimbi.Base.Repo.get_by!(Bilimbi.Core.Company.DepartmentType, code: "HR")
      view |> element("#delete-dept-type-#{hr.id}") |> render_click()
      refute has_element?(view, "#department-types td", "Human Resources")
    end
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
      grant_capabilities!(["admin.company.view"])

      {:ok, eng} =
        Bilimbi.Core.Company.create_department_type(%{
          code: "ENG",
          name: "Engineering",
          category: "operational"
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/departments")

      assert has_element?(view, "h1", "Bilimbi Industries — Departments")
      assert has_element?(view, "#company-departments-empty")

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

      # Remove
      view |> element("#delete-dept-#{dept.id}") |> render_click()
      assert has_element?(view, "#company-departments-empty")
    end
  end

  describe "Company Relationships Live" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies/73/relationships")
    end

    test "redirects without admin.company.view", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/73/relationships")
    end

    test "manages relationships and date edits", %{conn: conn} do
      CompanyFixtures.insert_relationship_type!(11)
      grant_capabilities!(["admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/relationships")

      assert has_element?(view, "h1", "Bilimbi Industries — Relationships")
      assert has_element?(view, "#company-relationships-empty")

      # Add Relationship
      view |> element("#add-rel-btn") |> render_click()
      assert has_element?(view, "#relationship-modal")

      view
      |> form("#relationship-form", %{
        "relationship" => %{
          "related_company_id" => "74",
          "relationship_type_id" => "11",
          "effective_from" => "2026-01-01",
          "effective_to" => "2026-12-31"
        }
      })
      |> render_submit()

      refute has_element?(view, "#relationship-modal")
      assert has_element?(view, "#company-relationships td", "Bilimbi Subsidiary")
      assert has_element?(view, "#company-relationships td", "Customer")
      assert has_element?(view, "#company-relationships span", "Outgoing")

      # Edit dates
      rel = Bilimbi.Base.Repo.get_by!(Bilimbi.Core.Company.Relationship, company_id: 73)
      view |> element("#edit-rel-#{rel.id}") |> render_click()
      assert has_element?(view, "#relationship-modal")

      view
      |> form("#relationship-form", %{
        "relationship" => %{
          "effective_to" => "2027-12-31"
        }
      })
      |> render_submit()

      assert has_element?(view, "#company-relationships", "2027-12-31")

      # Delete
      view |> element("#delete-rel-#{rel.id}") |> render_click()
      assert has_element?(view, "#company-relationships-empty")
    end
  end
end
