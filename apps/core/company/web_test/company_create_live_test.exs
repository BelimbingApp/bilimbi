defmodule BilimbiWeb.CompanyCreateLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Geonames.TestFixtures, as: GeonamesFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_legal_entity_types_table!()
    GeonamesFixtures.insert_country!(%{iso: "MY", country: "Malaysia"})

    CompanyFixtures.insert_tenant!(%{id: 41, is_platform_operator: true})

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

    CompanyFixtures.insert_company!(%{
      id: 75,
      tenant_id: 42,
      name: "Elsewhere",
      code: "elsewhere"
    })

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    :ok
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
      assert flash["success"] == "Company created successfully."

      {:ok, index, _html} = conn |> log_in_as() |> live(path)
      assert has_element?(index, "#companies td", "North Branch")

      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      created = Enum.find(companies, &(&1.name == "North Branch"))
      assert created.code == "north_branch"
    end

    test "company-scoped actor sees only their company as parent and cannot forge a sibling",
         %{conn: conn} do
      grant_capabilities!(["admin.company.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      assert has_element?(view, "#company-parent option[value='73']")
      refute has_element?(view, "#company-parent option[value='74']")
      refute has_element?(view, "#company-parent option[value='75']")

      render_submit(view, "save", %{
        "company" => %{
          "parent_id" => "74",
          "name" => "Forged Child",
          "status" => "active"
        }
      })

      assert has_element?(view, "#company-parent-error-0", "is not available")
      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Forged Child"))
    end

    test "forged non-positive parent ids fail closed without a write", %{conn: conn} do
      grant_capabilities!(["admin.company.create"])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      render_submit(view, "save", %{
        "company" => %{
          "parent_id" => "-1",
          "name" => "Invalid Parent Child",
          "status" => "active"
        }
      })

      assert has_element?(view, "#company-parent-error-0", "is not available")
      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Invalid Parent Child"))
    end

    # The route mounts under the create capability, so the host closes the
    # page at the next event once that grant is gone.
    test "revoking create capability after mount prevents a parentless write", %{conn: conn} do
      grant_capabilities!(["admin.company.create"])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")
      {:ok, scope} = Tenancy.scope(41)

      assert {:ok, :stored} =
               Bilimbi.Base.Authz.put_principal_capability(
                 scope,
                 73,
                 :user,
                 91,
                 "admin.company.create",
                 false
               )

      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               render_submit(view, "save", %{
                 "company" => %{
                   "parent_id" => "",
                   "name" => "Revoked Create",
                   "status" => "active"
                 }
               })

      assert assert_redirect(view, "/dashboard")["error"] ==
               BilimbiWeb.RouteAccess.revoked_message()

      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Revoked Create"))
    end

    test "tenant-wide company authority exposes sibling parents but not another tenant",
         %{conn: conn} do
      grant_capabilities!([
        "admin.company.create",
        "admin.company.tenant-wide.manage"
      ])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      assert has_element?(view, "#company-parent option[value='73']")
      assert has_element?(view, "#company-parent option[value='74']")
      refute has_element?(view, "#company-parent option[value='75']")

      view
      |> form("#company-form",
        company: %{parent_id: "74", name: "Authorized Child", status: "active"}
      )
      |> render_submit()

      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      assert Enum.any?(companies, &(&1.name == "Authorized Child" and &1.parent_id == 74))

      {:ok, forged, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      render_submit(forged, "save", %{
        "company" => %{
          "parent_id" => "75",
          "name" => "Cross Tenant Child",
          "status" => "active"
        }
      })

      assert has_element?(forged, "#company-parent-error-0", "is not available")
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Cross Tenant Child"))
    end

    test "rejects invalid JSON payloads without inserting", %{conn: conn} do
      grant_capabilities!(["admin.company.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      view
      |> form("#company-form",
        company: %{name: "Broken JSON Co", status: "active", metadata_json: "{not json"}
      )
      |> render_submit()

      assert has_element?(view, "#company-metadata-error-0", "must be valid JSON")
      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Broken JSON Co"))
    end

    test "renders jurisdiction country combobox and persists valid country", %{conn: conn} do
      grant_capabilities!(["admin.company.create", "admin.company.list", "admin.company.view"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      assert has_element?(view, "#company-jurisdiction[role='combobox']")
      assert has_element?(view, "#company-jurisdiction-option-MY[role='option']", "Malaysia (MY)")
      assert has_element?(view, "#company-jurisdiction[placeholder='Select country...']")

      assert has_element?(
               view,
               "#company-jurisdiction-value[name='company[jurisdiction]'][value='']"
             )

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

      view
      |> element("#company-form")
      |> render_submit(%{
        "company" => %{"name" => "Fake Co", "status" => "active", "jurisdiction" => "XX"}
      })

      assert has_element?(
               view,
               "#company-jurisdiction-error-0",
               "must be a valid country ISO code"
             )

      {:ok, scope} = Tenancy.scope(41)
      {:ok, companies} = Company.list_companies(scope)
      refute Enum.any?(companies, &(&1.name == "Fake Co"))
    end

    test "Name is visibly marked required on the real form", %{conn: conn} do
      grant_capabilities!(["admin.company.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      assert has_element?(view, "label[for='company-name']", "*")
    end

    test "a server-side required failure marks the Name field invalid", %{conn: conn} do
      grant_capabilities!(["admin.company.create"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      view
      |> element("#company-form")
      |> render_submit(%{"company" => %{"name" => "", "status" => "active"}})

      assert has_element?(view, "#company-name-error-0", "can't be blank")
      assert has_element?(view, "#company-name[aria-invalid='true']")
      assert has_element?(view, "#company-name[aria-describedby='company-name-error-0']")
      assert has_element?(view, "#company-name-error-0")
    end
  end

  describe "a restricted field" do
    test "is a read-only row that submits nothing, and the module refuses a forged value", %{
      conn: conn
    } do
      grant_capabilities!(["admin.company.list", "admin.company.create"])
      {:ok, scope} = Tenancy.scope(41)
      grant_capabilities!("admin.authz.field.manage", user_id: 92)
      operator = Bilimbi.Base.Tenancy.Authentication.sign_in(scope, 92, 73)
      {:ok, _} = Authz.put_field_restriction(operator, "companies", "email", [])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/create")

      assert has_element?(view, "#company-email-restricted[data-restricted-field]", "Email")
      assert has_element?(view, "#company-email-restricted [data-restricted]", "Restricted")
      refute has_element?(view, "input[name='company[email]']")
      assert has_element?(view, "input[name='company[tax_id]']")

      # A forged submit names the field the form never offered: the module
      # refuses the key and nothing is created.
      render_hook(view, "save", %{"company" => %{"name" => "Forged Co", "email" => "x@y.test"}})

      view
      |> form("#company-form", %{"company" => %{"name" => "Restricted Co"}})
      |> render_submit()

      reader = Bilimbi.Base.Tenancy.Authentication.sign_in(scope, 91, 73)
      {:ok, companies} = Company.list_companies(reader)
      refute Enum.any?(companies, &(&1.name == "Forged Co"))
      created = Enum.find(companies, &(&1.name == "Restricted Co"))
      assert created, "the form created the company without the restricted field"
      assert %Bilimbi.Base.Authz.Restricted{} = created.email

      {:ok, [restriction]} = Authz.list_field_restrictions(operator)
      assert {:ok, :removed} = Authz.remove_field_restriction(operator, restriction.id)
      assert {:ok, %{email: nil}} = Company.get_company(reader, created.id)
    end
  end
end
