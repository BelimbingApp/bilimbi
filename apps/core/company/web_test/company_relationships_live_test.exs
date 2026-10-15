defmodule BilimbiWeb.CompanyRelationshipsLiveTest do
  use BilimbiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.Relationship
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
      assert has_element?(view, "#company-relationships-card[role='region']")
      assert has_element?(view, "#company-relationships-heading", "Relationships")

      assert has_element?(
               view,
               "a#relationships-back[href='/companies/73'][title='Back to Bilimbi Industries']",
               "Back"
             )

      refute has_element?(view, "button#relationships-back")

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

      # Removing confirms through the shared dialog, which names the related
      # company and the relationship type and says what is lost.
      refute has_element?(view, "#delete-rel-#{rel.id}[data-confirm]")
      view |> element("#delete-rel-#{rel.id}") |> render_click()

      assert_modal_dialog(view, "delete-rel-confirm", "relationship with")
      assert has_element?(view, "dialog#delete-rel-confirm[role='alertdialog']")

      assert has_element?(
               view,
               "#delete-rel-confirm-description",
               "Both companies and the historical relationship are kept."
             )

      # Cancelling keeps the relationship.
      view |> element("#delete-rel-confirm-cancel", "Cancel") |> render_click()
      refute has_element?(view, "#delete-rel-confirm")
      refute has_element?(view, "#company-relationships-empty")

      # Confirming removes it and reports the completed write as a success.
      view |> element("#delete-rel-#{rel.id}") |> render_click()

      assert has_element?(
               view,
               "#delete-rel-confirm-confirm[phx-disable-with='Removing…']",
               "Remove"
             )

      view |> element("#delete-rel-confirm-confirm") |> render_click()
      refute has_element?(view, "#delete-rel-confirm")
      assert has_element?(view, "#flash-success", "Relationship removed.")
      assert has_element?(view, "#company-relationships-empty")
    end

    test "End relationship dates the end, defaults to today and keeps the row", %{conn: conn} do
      CompanyFixtures.insert_relationship_type!(11)
      grant_capabilities!(["admin.company.view", "admin.company.update"])
      {:ok, scope} = Tenancy.scope(41)

      {:ok, rel} =
        Company.create_relationship(scope, 73, %{
          "related_company_id" => "74",
          "relationship_type_id" => "11",
          "effective_from" => "2026-01-01"
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/relationships")
      view |> element("#end-rel-#{rel.id}") |> render_click()
      assert has_element?(view, "#relationship-modal")
      refute has_element?(view, "#relationship-effective-from")
      today = Date.to_iso8601(Date.utc_today())
      assert has_element?(view, "#relationship-effective-to[value='#{today}']")

      view
      |> form("#relationship-form", %{"relationship" => %{"effective_to" => "2026-03-31"}})
      |> render_submit()

      refute has_element?(view, "#relationship-modal")
      assert has_element?(view, "#flash-success", "Relationship ended")
      assert has_element?(view, "#company-relationships", "2026-03-31")

      render_hook(view, "save", %{"relationship" => %{"effective_to" => "2026-02-01"}})
      kept = Repo.get!(Relationship, rel.id)
      assert {kept.effective_to, kept.deleted_at} == {~D[2026-03-31], nil}
    end

    test "reopening an ended relationship beside an open one shows the refusal on the dialog", %{
      conn: conn
    } do
      CompanyFixtures.insert_relationship_type!(11)
      grant_capabilities!(["admin.company.view", "admin.company.update"])
      {:ok, scope} = Tenancy.scope(41)

      {:ok, ended} =
        Company.create_relationship(scope, 73, %{
          "related_company_id" => "74",
          "relationship_type_id" => "11",
          "effective_from" => "2025-01-01",
          "effective_to" => "2025-12-31"
        })

      {:ok, _open} =
        Company.create_relationship(scope, 73, %{
          "related_company_id" => "74",
          "relationship_type_id" => "11",
          "effective_from" => "2026-01-01"
        })

      {:ok, view, _html} = conn |> log_in_as() |> live(~p"/companies/73/relationships")

      view |> element("#edit-rel-#{ended.id}") |> render_click()

      view
      |> form("#relationship-form", %{"relationship" => %{"effective_to" => ""}})
      |> render_submit()

      assert has_element?(view, "#relationship-modal")

      assert has_element?(
               view,
               "#relationship-modal",
               "is already assigned between these companies for an overlapping period"
             )

      assert Repo.get!(Relationship, ended.id).effective_to == ~D[2025-12-31]
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
