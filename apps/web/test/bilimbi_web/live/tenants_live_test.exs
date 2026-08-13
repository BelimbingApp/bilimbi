defmodule BilimbiWeb.TenantsLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/tenancy/tenants")
  end

  test "redirects away when the actor lacks admin.tenancy.tenant.list", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/tenancy/tenants")
  end

  test "lists tenants when the actor has admin.tenancy.tenant.list", %{conn: conn} do
    grant_capabilities!("admin.tenancy.tenant.list")

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/tenancy/tenants")

    assert has_element?(view, "h1", "Tenants")
    assert has_element?(view, "#nav-admin-tenancy-tenant[aria-current='page']")
    assert has_element?(view, "#tenants")
    assert has_element?(view, "#tenants td", "Platform operator")
    refute has_element?(view, "#tenants-add")
  end

  test "refuses create without admin.tenancy.tenant.create and does not insert", %{conn: conn} do
    grant_capabilities!("admin.tenancy.tenant.list")
    before = Tenancy.count_tenants()

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/tenancy/tenants")

    render_click(view, "create", %{
      "tenant" => %{"name" => "Unauthorized Tenant", "status" => "active"}
    })

    assert has_element?(view, "#flash-error", "You do not have permission to create a tenant.")
    refute Enum.any?(Tenancy.list_tenants(), &(&1.name == "Unauthorized Tenant"))
    assert Tenancy.count_tenants() == before
  end

  test "creates a tenant when the actor has admin.tenancy.tenant.create", %{conn: conn} do
    grant_capabilities!(["admin.tenancy.tenant.list", "admin.tenancy.tenant.create"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/tenancy/tenants")

    assert has_element?(view, "#tenants-add")
    view |> element("#tenants-add") |> render_click()

    view
    |> form("#tenant-create-form",
      tenant: %{name: "Customer Sub-Tenant", parent_id: "41", status: "suspended"}
    )
    |> render_submit()

    assert has_element?(view, "#flash-info", "Tenant created.")
    assert has_element?(view, "#tenants td", "Customer Sub-Tenant")

    created = Enum.find(Tenancy.list_tenants(), &(&1.name == "Customer Sub-Tenant"))
    assert created.parent_id == 41
    assert created.status == "suspended"
  end
end
