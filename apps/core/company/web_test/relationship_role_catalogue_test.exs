defmodule BilimbiWeb.RelationshipRoleCatalogueTest do
  use BilimbiWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Bilimbi.Base.{AgentApi, Tenancy}
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Company

  setup do
    signed_in_identity!()
    Company.TestFixtures.create_external_access_tables!()
    AgentApi.TestFixtures.create_plan_tables!()
    {:ok, system} = Tenancy.scope(41)
    %{scope: Authentication.sign_in(system, 91, 73)}
  end

  test "UI manages custom role names and retirement while keeping historical links", %{
    conn: conn,
    scope: scope
  } do
    grant_capabilities!(
      ~w(admin.company.list admin.company.view admin.company.create admin.company.update)
    )

    Company.TestFixtures.insert_company!(%{id: 74, code: "vendor"})
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/companies/relationship-types")
    view |> element("#new-relationship-type-btn") |> render_click()

    view
    |> form("#relationship-type-form",
      relationship_type: %{code: "custom_supplier", name: "Supplier", inverse_name: "Buyer"}
    )
    |> render_submit()

    assert has_element?(view, "#flash-success", "Relationship role created successfully.")

    {:ok, [role]} = Company.list_relationship_types()

    {:ok, rel} =
      Company.create_relationship(scope, 73, %{
        related_company_id: 74,
        relationship_type_id: role.id
      })

    view |> element("#edit-type-#{role.id}") |> render_click()

    view
    |> form("#relationship-type-form",
      relationship_type: %{name: "Vendor", inverse_name: "Customer"}
    )
    |> render_submit()

    assert has_element?(view, "#flash-success", "Relationship role updated successfully.")

    view |> element("#toggle-type-#{role.id}") |> render_click()

    assert {:ok, %{id: id, name: "Vendor", is_active: false}} =
             Company.get_relationship_type(role.id)

    assert id == role.id
    assert {:ok, [%{id: rel_id, role_label: "Vendor"}]} = Company.list_relationships(scope, 73)
    assert rel_id == rel.id
    refute has_element?(view, "#delete-type-#{role.id}")
  end

  test "catalogue agent operations use reviewed plans and preserve stable role codes", %{
    scope: scope
  } do
    grant_capabilities!(~w(admin.company.list admin.company.create admin.company.update))

    op = %{
      "key" => "core.company.relationship_role.create",
      "input" => %{"code" => "custom", "name" => "Supplier", "inverse_name" => "Buyer"}
    }

    {:ok, plan} = AgentApi.plan(scope, [op])
    assert plan["valid"]
    assert {:ok, []} = Company.list_relationship_types()
    assert {:ok, _} = AgentApi.commit(scope, plan["plan_code"], [op])
    {:ok, [role]} = Company.list_relationship_types()
    assert role.code == "custom"

    update = %{
      "key" => "core.company.relationship_role.update",
      "input" => %{"role_id" => role.id, "name" => "Vendor"}
    }

    {:ok, plan} = AgentApi.plan(scope, [update])
    assert plan["valid"]
    assert {:ok, _} = AgentApi.commit(scope, plan["plan_code"], [update])

    assert {:ok, %{id: id, code: "custom", name: "Vendor"}} =
             Company.get_relationship_type(role.id)

    assert id == role.id
  end

  test "read-only users cannot forge catalogue writes through UI or operations", %{
    conn: conn,
    scope: scope
  } do
    grant_capabilities!("admin.company.list")
    {:ok, view, _} = conn |> log_in_as() |> live(~p"/companies/relationship-types")
    render_submit(view, "save", %{"relationship_type" => %{"code" => "bad", "name" => "Bad"}})
    assert {:ok, []} = Company.list_relationship_types()

    assert {:ok, %{"valid" => false}} =
             AgentApi.plan(scope, [
               %{
                 "key" => "core.company.relationship_role.create",
                 "input" => %{"code" => "bad", "name" => "Bad", "inverse_name" => "Bad"}
               }
             ])
  end

  test "non-operator tenants cannot manage the shared catalogue through UI or agent plans", %{
    conn: conn
  } do
    Company.TestFixtures.insert_tenant!(%{id: 42, is_platform_operator: false})
    Company.TestFixtures.insert_company!(%{id: 75, tenant_id: 42, code: "foreign"})

    Bilimbi.Core.User.TestFixtures.insert_user!(%{
      id: 92,
      company_id: 75,
      email: "foreign@example.test"
    })

    grant_capabilities!(~w(admin.company.list admin.company.create admin.company.update),
      tenant_id: 42,
      company_id: 75,
      user_id: 92
    )

    {:ok, tenant} = Tenancy.scope(42)
    scope = Authentication.sign_in(tenant, 92, 75)
    other = log_in_as(conn, session_user(%{"user_id" => 92, "company_id" => 75}))

    assert {:ok, view, _} = live(other, ~p"/companies/relationship-types")
    assert has_element?(view, "#relationship-roles-readonly")
    refute has_element?(view, "#new-relationship-type-btn")

    render_submit(view, "save", %{
      "relationship_type" => %{"code" => "bad", "name" => "Bad", "inverse_name" => "Bad"}
    })

    op = %{
      "key" => "core.company.relationship_role.create",
      "input" => %{"code" => "bad", "name" => "Bad", "inverse_name" => "Bad"}
    }

    assert {:ok, %{"valid" => false}} = AgentApi.plan(scope, [op])
    assert {:ok, []} = Company.list_relationship_types()
  end

  test "agent relationship plans support simultaneous roles, dates and retained unlink; foreign targets are denied",
       %{scope: scope} do
    grant_capabilities!(
      ~w(admin.company.list admin.company.view admin.company.create admin.company.update)
    )

    Company.TestFixtures.insert_company!(%{id: 74, code: "vendor"})
    Company.TestFixtures.insert_tenant!(%{id: 42, is_platform_operator: false})
    Company.TestFixtures.insert_company!(%{id: 75, tenant_id: 42, code: "foreign"})
    :ok = Bilimbi.Core.Company.RelationshipCatalogue.ensure_defaults(Bilimbi.Base.Repo)
    {:ok, roles} = Company.list_relationship_types()
    selected = Enum.filter(roles, &(&1.code in ["vendor", "customer"]))

    ops =
      Enum.map(selected, fn role ->
        %{
          "key" => "core.company.relationship.create",
          "input" => %{
            "company_id" => 73,
            "related_company_id" => 74,
            "relationship_type_id" => role.id
          }
        }
      end)

    {:ok, plan} = AgentApi.plan(scope, ops)
    assert plan["valid"]
    assert {:ok, _} = AgentApi.commit(scope, plan["plan_code"], ops)
    assert {:ok, rows} = Company.list_relationships(scope, 73)
    assert length(rows) == 2
    [rel | _] = rows

    update = %{
      "key" => "core.company.relationship.update",
      "input" => %{
        "company_id" => 73,
        "relationship_id" => rel.id,
        "effective_to" => "2028-01-01"
      }
    }

    {:ok, plan} = AgentApi.plan(scope, [update])
    assert plan["valid"]
    assert {:ok, _} = AgentApi.commit(scope, plan["plan_code"], [update])

    unlink = %{
      "key" => "core.company.relationship.unlink",
      "input" => %{"company_id" => 73, "relationship_id" => rel.id}
    }

    {:ok, plan} = AgentApi.plan(scope, [unlink])
    assert plan["valid"]
    assert {:ok, _} = AgentApi.commit(scope, plan["plan_code"], [unlink])
    retained = Bilimbi.Base.Repo.get!(Bilimbi.Core.Company.Relationship, rel.id)
    assert retained.effective_to == ~D[2028-01-01]
    assert retained.deleted_at != nil

    assert {:ok, %{"result" => %{"id" => retained_id, "unlinked_at" => clock}}} =
             AgentApi.call(scope, "core.company.relationship.get", %{
               "company_id" => 73,
               "relationship_id" => rel.id
             })

    assert retained_id == rel.id
    assert is_binary(clock)

    assert {:ok, %{"result" => history}} =
             AgentApi.call(scope, "core.company.relationship.list", %{
               "company_id" => 73,
               "include_unlinked" => true
             })

    assert length(history) == 2
    foreign = put_in(hd(ops), ["input", "related_company_id"], 75)
    assert {:ok, %{"valid" => false}} = AgentApi.plan(scope, [foreign])

    assert {:ok, _} =
             Bilimbi.Base.Authz.put_principal_capability(
               scope,
               73,
               :user,
               91,
               "admin.company.update",
               false
             )

    assert {:ok, %{"valid" => false}} = AgentApi.plan(scope, [hd(ops)])
  end

  test "agents end a relationship on a date, keeping it as dated history; preview does not mutate",
       %{scope: scope} do
    grant_capabilities!(
      ~w(admin.company.list admin.company.view admin.company.create admin.company.update)
    )

    Company.TestFixtures.insert_company!(%{id: 74, code: "vendor"})
    :ok = Bilimbi.Core.Company.RelationshipCatalogue.ensure_defaults(Bilimbi.Base.Repo)
    {:ok, roles} = Company.list_relationship_types()
    prospect = Enum.find(roles, &(&1.code == "prospect"))

    {:ok, rel} =
      Company.create_relationship(scope, 73, %{
        related_company_id: 74,
        relationship_type_id: prospect.id,
        effective_from: "2026-01-01"
      })

    end_op = %{
      "key" => "core.company.relationship.end",
      "input" => %{
        "company_id" => 73,
        "relationship_id" => rel.id,
        "effective_to" => "2026-03-31"
      }
    }

    {:ok, plan} = AgentApi.plan(scope, [end_op])
    assert plan["valid"]
    assert Bilimbi.Base.Repo.get!(Bilimbi.Core.Company.Relationship, rel.id).effective_to == nil
    assert {:ok, _} = AgentApi.commit(scope, plan["plan_code"], [end_op])
    kept = Bilimbi.Base.Repo.get!(Bilimbi.Core.Company.Relationship, rel.id)
    assert kept.effective_to == ~D[2026-03-31]
    assert kept.deleted_at == nil

    bad = put_in(end_op, ["input", "effective_to"], "2025-12-31")
    assert {:ok, %{"valid" => false}} = AgentApi.plan(scope, [bad])
  end

  test "relationship create and update accept only the inputs they apply", %{scope: scope} do
    grant_capabilities!(
      ~w(admin.company.list admin.company.view admin.company.create admin.company.update)
    )

    Company.TestFixtures.insert_company!(%{id: 74, code: "vendor"})
    :ok = Bilimbi.Core.Company.RelationshipCatalogue.ensure_defaults(Bilimbi.Base.Repo)
    {:ok, roles} = Company.list_relationship_types()
    vendor = Enum.find(roles, &(&1.code == "vendor"))
    customer = Enum.find(roles, &(&1.code == "customer"))

    {:ok, rel} =
      Company.create_relationship(scope, 73, %{
        related_company_id: 74,
        relationship_type_id: vendor.id
      })

    retype = %{
      "key" => "core.company.relationship.update",
      "input" => %{
        "company_id" => 73,
        "relationship_id" => rel.id,
        "relationship_type_id" => customer.id
      }
    }

    assert {:ok, %{"valid" => false}} = AgentApi.plan(scope, [retype])

    plain_update = %{
      "key" => "core.company.relationship.update",
      "input" => %{
        "company_id" => 73,
        "relationship_id" => rel.id,
        "effective_to" => "2030-01-01"
      }
    }

    assert {:ok, %{"valid" => true}} = AgentApi.plan(scope, [plain_update])

    stray_id = %{
      "key" => "core.company.relationship.create",
      "input" => %{
        "company_id" => 73,
        "related_company_id" => 74,
        "relationship_type_id" => customer.id,
        "relationship_id" => rel.id
      }
    }

    assert {:ok, %{"valid" => false}} = AgentApi.plan(scope, [stray_id])

    assert {:ok, %{"valid" => true}} =
             AgentApi.plan(scope, [
               put_in(stray_id, ["input"], Map.delete(stray_id["input"], "relationship_id"))
             ])
  end
end
