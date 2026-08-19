defmodule BilimbiWeb.CompanyLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.{Department, DepartmentType, LegalEntityType, Relationship}
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    GeonamesFixtures.create_geonames_tables!()
    GeonamesFixtures.insert_country!(%{iso: "MY", country: "Malaysia"})
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
      refute has_element?(view, "#companies-add")
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

  describe "Create" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/companies/create")
    end

    test "redirects away when the actor lacks admin.company.create", %{conn: conn} do
      grant_capabilities!(["admin.company.list"])

      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as() |> live(~p"/companies/create")
    end

    test "shows the add control on the index when the actor can create", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies")

      assert has_element?(view, "#companies-add[href='/companies/create']")
    end

    test "creates a company through the domain API and slugs a blank code", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.create", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      view
      |> form("#company-form", company: %{name: "North Branch", status: "active"})
      |> render_submit()

      {path, flash} = assert_redirect(view)
      assert path == "/companies"
      assert flash["info"] == "Company created successfully."

      {:ok, index, _html} = conn |> log_in_as() |> live(path)
      assert has_element?(index, "#companies td", "North Branch")

      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      created = Enum.find(companies, &(&1.name == "North Branch"))
      assert created.code == "north_branch"
    end

    test "rejects invalid JSON payloads without inserting", %{conn: conn} do
      grant_capabilities!(["admin.company.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      html =
        view
        |> form("#company-form",
          company: %{name: "Broken JSON Co", status: "active", metadata_json: "{not json"}
        )
        |> render_submit()

      assert html =~ "must be valid JSON"
      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Broken JSON Co"))
    end

    test "renders jurisdiction country select and persists valid country", %{conn: conn} do
      grant_capabilities!(["admin.company.create", "admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      assert has_element?(view, "#company-jurisdiction")
      assert has_element?(view, "#company-jurisdiction option[value='MY']", "Malaysia (MY)")

      # Belimbing labels each select's empty option differently and on purpose:
      # "None" for Parent Company, "Select type..." for Legal Entity Type,
      # "Select country..." here (`create.blade.php:88`).
      assert has_element?(view, "#company-jurisdiction option[value='']", "Select country...")

      view
      |> form("#company-form",
        company: %{name: "MY Branch", status: "active", jurisdiction: "MY"}
      )
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path == "/companies"

      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      created = Enum.find(companies, &(&1.name == "MY Branch"))
      assert Repo.get!(Bilimbi.Core.Company.Schema, created.id).jurisdiction == "MY"
    end

    test "rejects forged invalid country ISO without persisting", %{conn: conn} do
      grant_capabilities!(["admin.company.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      html =
        view
        |> element("#company-form")
        |> render_submit(%{
          "company" => %{"name" => "Fake Co", "status" => "active", "jurisdiction" => "XX"}
        })

      assert html =~ "must be a valid country ISO code"
      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Fake Co"))
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
      grant_capabilities!([
        "admin.company.list",
        "admin.company.create",
        "admin.company.update",
        "admin.company.delete"
      ])

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

    test "hides write controls and rejects direct write events without write capabilities", %{
      conn: conn
    } do
      {:ok, type} =
        Company.create_legal_entity_type(%{
          code: "LLC",
          name: "Limited Liability Company",
          is_active: true
        })

      grant_capabilities!(["admin.company.list"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/legal-entity-types")

      refute has_element?(view, "#new-legal-entity-type-btn")
      refute has_element?(view, "#toggle-type-#{type.id}")
      refute has_element?(view, "#edit-type-#{type.id}")
      refute has_element?(view, "#delete-type-#{type.id}")

      render_click(view, "toggle_active", %{"id" => to_string(type.id)})
      render_click(view, "delete", %{"id" => to_string(type.id)})

      render_submit(view, "save", %{
        "legal_entity_type" => %{"code" => "NEW", "name" => "Unauthorized"}
      })

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      assert Repo.get!(LegalEntityType, type.id).is_active
      refute Repo.get_by(LegalEntityType, code: "NEW")
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
      grant_capabilities!([
        "admin.company.list",
        "admin.company.create",
        "admin.company.update",
        "admin.company.delete"
      ])

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

    test "hides write controls and rejects direct write events without write capabilities", %{
      conn: conn
    } do
      {:ok, type} =
        Company.create_department_type(%{
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

    test "hides write controls and rejects direct write events without update capability", %{
      conn: conn
    } do
      {:ok, type} =
        Company.create_department_type(%{
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

      render_click(view, "update_status", %{
        "id" => to_string(department.id),
        "status" => "suspended"
      })

      render_click(view, "delete", %{"id" => to_string(department.id)})

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
      grant_capabilities!(["admin.company.view", "admin.company.update"])

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

    test "hides write controls and rejects direct write events without update capability", %{
      conn: conn
    } do
      CompanyFixtures.insert_relationship_type!(11)
      {:ok, scope} = Tenancy.scope(41)

      {:ok, relationship} =
        Company.create_relationship(scope, 73, %{
          "related_company_id" => "74",
          "relationship_type_id" => "11",
          "effective_from" => "2026-01-01"
        })

      grant_capabilities!(["admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/relationships")

      refute has_element?(view, "#add-rel-btn")
      refute has_element?(view, "#edit-rel-#{relationship.id}")
      refute has_element?(view, "#delete-rel-#{relationship.id}")

      render_click(view, "delete", %{"id" => to_string(relationship.id)})

      render_submit(view, "save", %{
        "relationship" => %{
          "related_company_id" => "74",
          "relationship_type_id" => "11",
          "effective_from" => "2026-02-01"
        }
      })

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      assert is_nil(Repo.get!(Relationship, relationship.id).deleted_at)
      assert Repo.aggregate(Relationship, :count) == 1
    end
  end
end
