defmodule BilimbiWeb.CompanySealedScopeLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.create_legal_entity_types_table!()
    CompanyFixtures.create_external_access_tables!()

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

    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    :ok
  end

  describe "type and relationship writes re-check the sealed scope" do
    test "the API refuses a person who no longer holds the write capability" do
      scope = scope!()
      user = Bilimbi.Base.Tenancy.Authentication.sign_in(scope, 91, 73)

      assert {:error, :forbidden} =
               Company.create_legal_entity_type(user, %{code: "NOPE", name: "Nope"})

      assert {:error, :forbidden} =
               Company.create_department_type(user, %{code: "NOPE", name: "Nope"})

      assert {:error, :forbidden} =
               Company.create_relationship(user, 73, %{"related_company_id" => "74"})

      assert {:ok, _} = Company.create_legal_entity_type(scope, %{code: "SYS", name: "System"})

      grant_capabilities!("admin.company.create")

      assert {:ok, %{code: "OK"}} =
               Company.create_legal_entity_type(user, %{code: "OK", name: "Allowed"})
    end

    test "refuses a legal entity type create after the capability is revoked", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.create"])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/legal-entity-types")
      view |> element("#new-legal-entity-type-btn") |> render_click()
      assert has_element?(view, "#legal-entity-type-form")

      revoke_capability!(scope!(), "admin.company.create")

      view
      |> form("#legal-entity-type-form", %{
        "legal_entity_type" => %{"code" => "REV", "name" => "Revoked"}
      })
      |> render_submit()

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      assert {:ok, types} = Company.list_legal_entity_types()
      refute Enum.any?(types, &(&1.code == "REV"))
    end

    test "refuses a department type create after the capability is revoked", %{conn: conn} do
      grant_capabilities!(["admin.company.list", "admin.company.create"])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/department-types")
      view |> element("#new-department-type-btn") |> render_click()
      assert has_element?(view, "#department-type-form")

      revoke_capability!(scope!(), "admin.company.create")

      view
      |> form("#department-type-form", %{
        "department_type" => %{
          "code" => "REV",
          "name" => "Revoked",
          "category" => "operational"
        }
      })
      |> render_submit()

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      assert {:ok, types} = Company.list_department_types()
      refute Enum.any?(types, &(&1.code == "REV"))
    end

    test "refuses a relationship create after the capability is revoked", %{conn: conn} do
      CompanyFixtures.insert_relationship_type!(11)
      grant_capabilities!(["admin.company.view", "admin.company.update"])
      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/relationships")
      view |> element("#add-rel-btn") |> render_click()
      assert has_element?(view, "#relationship-form")

      revoke_capability!(scope!(), "admin.company.update")

      view
      |> form("#relationship-form", %{
        "relationship" => %{
          "related_company_id" => "74",
          "relationship_type_id" => "11",
          "effective_from" => "2026-01-01"
        }
      })
      |> render_submit()

      assert has_element?(
               view,
               "#flash-error",
               "You do not have permission to change company administration data."
             )

      assert {:ok, []} = Company.list_relationships(scope!(), 73)
    end
  end

  defp scope! do
    {:ok, scope} = Tenancy.scope(41)
    scope
  end
end
