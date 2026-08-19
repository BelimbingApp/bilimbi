defmodule BilimbiWeb.EmployeeTypeLiveTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok = Employee.ensure_system_types()
    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/employee-types")
  end

  test "redirects away when the actor lacks admin.employee-type.list", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/employee-types")
  end

  test "lists system types", %{conn: conn} do
    grant_capabilities!(["admin.employee.list", "admin.employee-type.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    assert has_element?(view, "#nav-admin-employee-type[aria-current='page']")
    assert has_element?(view, "#employee-types td", "Full Time")
    assert has_element?(view, "#employee-types td", "Agent")
    refute has_element?(view, "#employee-type-new")
  end

  test "creates a custom type", %{conn: conn} do
    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.create"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types/new")

    view
    |> form("#employee-type-form", employee_type: %{code: "seasonal", label: "Seasonal"})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path == "/employee-types"

    {:ok, index, _html} = conn |> log_in_as() |> live(path)
    assert has_element?(index, "#employee-types td", "Seasonal")

    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, types} = Employee.list_employee_types(scope, 73)
    assert Enum.any?(types, &(&1.code == "seasonal" and not &1.is_system))
  end

  test "updates a custom type", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, type} =
      Employee.create_employee_type(scope, 73, %{
        code: "temp_contractor",
        label: "Temporary Contractor"
      })

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types/#{type.id}/edit")

    view
    |> form("#employee-type-form", employee_type: %{label: "Independent Contractor"})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path == "/employee-types"

    {:ok, index, _html} = conn |> log_in_as() |> live(path)
    assert has_element?(index, "#employee-types td", "Independent Contractor")

    assert {:ok, updated} = Employee.get_employee_type(scope, 73, type.id)
    assert updated.label == "Independent Contractor"
    assert updated.code == "temp_contractor"
  end

  test "forbids editing a system type", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)
    {:ok, types} = Employee.list_employee_types(scope, 73)
    system_type = Enum.find(types, & &1.is_system)

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.update"])

    assert {:error,
            {:live_redirect,
             %{
               to: "/employee-types",
               flash: %{"error" => "System employee types cannot be edited."}
             }}} =
             conn |> log_in_as() |> live(~p"/employee-types/#{system_type.id}/edit")
  end

  test "deletes a custom type", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, type} =
      Employee.create_employee_type(scope, 73, %{
        code: "temp",
        label: "Temporary"
      })

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")
    assert has_element?(view, "#employee-type-delete-#{type.id}[phx-disable-with='Deleting…']")

    view
    |> element("#employee-type-delete-#{type.id}")
    |> render_click()

    refute has_element?(view, "#employee-types td", "Temporary")
    assert render(view) =~ "Employee type deleted."

    assert {:error, :type_not_found} = Employee.get_employee_type(scope, 73, type.id)
  end

  test "rejects deleting an in-use custom type", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, type} =
      Employee.create_employee_type(scope, 73, %{
        code: "consultant",
        label: "Consultant"
      })

    {:ok, _employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-0099",
        full_name: "Grace Hopper",
        short_name: "Grace",
        designation: "Lead Consultant",
        employee_type: "consultant",
        email: "grace@navy.mil",
        status: "active"
      })

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    view
    |> element("#employee-type-delete-#{type.id}")
    |> render_click()

    assert render(view) =~ "Cannot delete: employees are using this type."
    assert {:ok, _} = Employee.get_employee_type(scope, 73, type.id)
  end

  test "system types do not show edit or delete action links", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)
    {:ok, types} = Employee.list_employee_types(scope, 73)
    system_type = Enum.find(types, & &1.is_system)

    grant_capabilities!([
      "admin.employee-type.list",
      "admin.employee-type.update",
      "admin.employee-type.delete"
    ])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    refute has_element?(view, "#employee-type-edit-#{system_type.id}")
    refute has_element?(view, "#employee-type-delete-#{system_type.id}")
  end

  test "renders empty state when no employee types exist", %{conn: conn} do
    Bilimbi.Base.Repo.delete_all(Bilimbi.Core.Employee.EmployeeType)
    grant_capabilities!(["admin.employee-type.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")
    assert has_element?(view, "#employee-types-empty", "No employee types found.")
  end

  test "filters employee types by search query", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, _type} =
      Employee.create_employee_type(scope, 73, %{
        code: "temporary_contractor",
        label: "Specialist Consultant"
      })

    grant_capabilities!(["admin.employee-type.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    assert has_element?(view, "#employee-types td", "Specialist Consultant")
    assert has_element?(view, "#employee-types td", "Full Time")

    view
    |> form("#employee-types-filters", filters: %{search: "Specialist"})
    |> render_change()

    assert_patched(view, ~p"/employee-types?search=Specialist")
    assert has_element?(view, "#employee-types td", "Specialist Consultant")
    refute has_element?(view, "#employee-types td", "Full Time")

    # Direct URL navigation
    {:ok, search_view, _html} =
      conn |> log_in_as() |> live(~p"/employee-types?search=temporary")

    assert has_element?(search_view, "#employee-types td", "Specialist Consultant")
    refute has_element?(search_view, "#employee-types td", "Full Time")
  end

  test "sorts employee types by column headers with aria-sort", %{conn: conn} do
    grant_capabilities!(["admin.employee-type.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    # Default sort is is_system desc
    assert has_element?(view, "th[aria-sort='descending']", "Kind")

    # Sort by code
    view |> element("#employee-types-sort-code") |> render_click()
    assert_patched(view, ~p"/employee-types?sort=code")
    assert has_element?(view, "th[aria-sort='ascending']", "Code")

    # Toggle code desc
    view |> element("#employee-types-sort-code") |> render_click()
    assert_patched(view, ~p"/employee-types?dir=desc&sort=code")
    assert has_element?(view, "th[aria-sort='descending']", "Code")

    # Sort by label
    view |> element("#employee-types-sort-label") |> render_click()
    assert_patched(view, ~p"/employee-types?sort=label")
    assert has_element?(view, "th[aria-sort='ascending']", "Label")

    # Sort by employees count
    view |> element("#employee-types-sort-employees") |> render_click()
    assert_patched(view, ~p"/employee-types?sort=employees_count")
    assert has_element?(view, "th[aria-sort='descending']", "Employees")
  end

  test "paginates employee types and normalizes invalid query parameters", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    for i <- 1..25 do
      code = "type_#{String.pad_leading("#{i}", 2, "0")}"
      label = "Custom Type #{String.pad_leading("#{i}", 2, "0")}"

      {:ok, _} =
        Employee.create_employee_type(scope, 73, %{
          code: code,
          label: label
        })
    end

    grant_capabilities!(["admin.employee-type.list"])

    # 5 system types + 25 custom types = 30 total types
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    assert has_element?(
             view,
             "#employee-types-pagination-summary",
             "Showing 1 to 25 of 30 results"
           )

    # Change per_page to 50
    view
    |> form("#employee-types-pagination-page-size-form", filters: %{perPage: "50"})
    |> render_change()

    assert_patched(view, ~p"/employee-types?per_page=50")

    assert has_element?(
             view,
             "#employee-types-pagination-summary",
             "Showing 1 to 30 of 30 results"
           )

    # Invalid per_page falls back to 25
    {:ok, invalid_view, _html} =
      conn |> log_in_as() |> live(~p"/employee-types?per_page=12")

    assert has_element?(
             invalid_view,
             "#employee-types-pagination-summary",
             "Showing 1 to 25 of 30 results"
           )
  end

  test "clamps page when deleting the last item on page", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    for i <- 1..20 do
      code = "type_#{String.pad_leading("#{i}", 2, "0")}"
      label = "Custom Type #{String.pad_leading("#{i}", 2, "0")}"

      {:ok, _} =
        Employee.create_employee_type(scope, 73, %{
          code: code,
          label: label
        })
    end

    {:ok, to_delete} =
      Employee.create_employee_type(scope, 73, %{
        code: "type_last_page",
        label: "Last Page Type"
      })

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.delete"])

    # 5 system types + 21 custom = 26 total types -> page 2 has 1 item (item 26 of 26)
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types?page=2")

    assert has_element?(view, "#employee-type-delete-#{to_delete.id}")

    assert has_element?(
             view,
             "#employee-types-pagination-summary",
             "Showing 26 to 26 of 26 results"
           )

    view |> element("#employee-type-delete-#{to_delete.id}") |> render_click()

    assert render(view) =~ "Employee type deleted."
    refute has_element?(view, "#employee-types td", "Last Page Type")

    # Clamped back to page 1
    assert_patched(view, ~p"/employee-types")

    assert has_element?(
             view,
             "#employee-types-pagination-summary",
             "Showing 1 to 25 of 25 results"
           )
  end

  test "the heading matches the nav label that leads here", %{conn: conn} do
    grant_capabilities!("admin.employee-type.list")
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    # Derived from the contribution rather than repeated as a literal: the nav
    # label is the source of truth, and the page used to say "Employee types"
    # while the menu item said "Employee Types" (#291).
    label =
      Bilimbi.Core.Employee.Contributions.contributions().menu
      |> Enum.find(&(&1.id == "admin.employee-type"))
      |> Map.fetch!(:label)

    assert render(view) =~ label
  end

  test "the primary action is Title Case like every other index screen", %{conn: conn} do
    # `create` as well as `list`: the action is capability-gated, so with only
    # `list` the element does not render and the assertion fails for a reason
    # that has nothing to do with its label.
    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.create"])
    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    # A literal, unlike the heading test above, because button labels have no
    # contribution to derive from -- the nav owns page names, nothing owns
    # action names. #292 fixed the titles and left this one behind, so it is
    # pinned rather than trusted (#296).
    assert has_element?(view, "#employee-type-new", "New Type")
  end
end
