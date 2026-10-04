defmodule BilimbiWeb.LegalEntityTypesLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.LegalEntityType
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
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
      id: 75,
      tenant_id: 42,
      name: "Elsewhere",
      code: "elsewhere"
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

  test "a non-operator tenant cannot add platform-wide legal entity types", %{conn: conn} do
    grant_capabilities!("admin.company.list",
      tenant_id: 42,
      company_id: 75,
      user_id: 96
    )

    conn = log_in_as(conn, session_user(%{"user_id" => 96, "company_id" => 75}))

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             live(conn, ~p"/companies/legal-entity-types")

    assert {:ok, []} = Company.list_legal_entity_types()
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
      assert has_element?(view, "#nav-admin-company-legal-entity-type[aria-current='page']")
      assert has_element?(view, "#legal-entity-types-empty", "No legal entity types defined yet.")

      assert has_element?(
               view,
               "a#legal-entity-types-back[href='/companies'][title='Back to companies']",
               "Back"
             )

      refute has_element?(view, "button#legal-entity-types-back")

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

      # Delete confirms through the shared dialog, which leads with the
      # consequence and says what cannot be undone; no native confirm remains.
      refute has_element?(view, "#delete-type-#{type.id}[data-confirm]")
      view |> element("#delete-type-#{type.id}") |> render_click()

      assert_modal_dialog(
        view,
        "delete-type-confirm",
        "Legal entity type “Limited Liability Corp” will be deleted."
      )

      assert has_element?(view, "dialog#delete-type-confirm[role='alertdialog']")

      assert has_element?(
               view,
               "#delete-type-confirm-description",
               "It can no longer be chosen for a company. This cannot be undone."
             )

      # Cancelling keeps the type.
      view |> element("#delete-type-confirm-cancel", "Cancel") |> render_click()
      refute has_element?(view, "#delete-type-confirm")
      assert has_element?(view, "#legal-entity-types td", "Limited Liability Corp")
      assert Repo.get(LegalEntityType, type.id)

      # Confirming deletes it and reports the completed write as a success.
      view |> element("#delete-type-#{type.id}") |> render_click()

      assert has_element?(
               view,
               "#delete-type-confirm-confirm[phx-disable-with='Deleting…']",
               "Delete"
             )

      view |> element("#delete-type-confirm-confirm") |> render_click()
      refute has_element?(view, "#delete-type-confirm")
      assert has_element?(view, "#flash-success", "Legal entity type deleted.")
      assert has_element?(view, "#legal-entity-types-empty", "No legal entity types defined yet.")
      refute Repo.get(LegalEntityType, type.id)
    end

    test "refuses to delete a legal entity type in use and says what to do", %{conn: conn} do
      {:ok, type} =
        Company.create_legal_entity_type(scope!(), %{
          code: "LLC",
          name: "Limited Liability Company"
        })

      CompanyFixtures.insert_company!(%{
        id: 76,
        tenant_id: 41,
        name: "Uses LLC",
        code: "uses_llc",
        legal_entity_type_id: type.id
      })

      grant_capabilities!(["admin.company.list", "admin.company.delete"])

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/legal-entity-types")

      view |> element("#delete-type-#{type.id}") |> render_click()
      view |> element("#delete-type-confirm-confirm") |> render_click()

      refute has_element?(view, "#delete-type-confirm")

      assert has_element?(
               view,
               "#flash-error",
               "Limited Liability Company was not deleted: one or more companies still use it. " <>
                 "Change those companies' legal entity type first."
             )

      assert has_element?(view, "#legal-entity-types td", "Limited Liability Company")
      assert Repo.get(LegalEntityType, type.id)
    end

    test "hides write controls and rejects direct write events without write capabilities", %{
      conn: conn
    } do
      {:ok, type} =
        Company.create_legal_entity_type(scope!(), %{
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

  defp scope! do
    {:ok, scope} = Tenancy.scope(41)
    scope
  end
end
