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

    assert has_element?(
             view,
             "a#employee-types-back[href='/employees'][title='Back to employees']",
             "Back"
           )

    refute has_element?(view, "button#employee-types-back")
  end

  test "creates a custom type", %{conn: conn} do
    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.create"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types/new")

    assert has_element?(
             view,
             "a#employee-type-form-back[href='/employee-types'][title='Back to employee types']",
             "Back"
           )

    refute has_element?(view, "button#employee-type-form-back")

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

  test "the list's Edit action opens the type's read-first record page", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, type} =
      Employee.create_employee_type(scope, 73, %{
        code: "temp_contractor",
        label: "Temporary Contractor"
      })

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    # The action keeps its capability gate and its glyph; it leads to the
    # record page, where the label edits in place, not to a separate form.
    assert has_element?(view, "a#employee-type-edit-#{type.id}[href='/employee-types/#{type.id}']")
    refute has_element?(view, "a[href$='/edit']")

    {:ok, show, _html} =
      view
      |> element("#employee-type-edit-#{type.id}")
      |> render_click()
      |> follow_redirect(conn |> log_in_as(), ~p"/employee-types/#{type.id}")

    assert has_element?(show, "#employee-type-label[phx-hook='InlineEdit']")
  end

  test "a list-only viewer reaches a type's record page from its label", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)
    {:ok, type} = Employee.create_employee_type(scope, 73, %{code: "temp", label: "Temporary"})

    grant_capabilities!(["admin.employee-type.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    refute has_element?(view, "#employee-type-edit-#{type.id}")

    {:ok, show, _html} =
      view
      |> element("a#employee-type-#{type.id}-link[href='/employee-types/#{type.id}']", "Temporary")
      |> render_click()
      |> follow_redirect(conn |> log_in_as(), ~p"/employee-types/#{type.id}")

    assert has_element?(show, "h1", "Temporary")
  end

  test "a system type's label links to its record page", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)
    {:ok, types} = Employee.list_employee_types(scope, 73)
    system_type = Enum.find(types, & &1.is_system)

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    refute has_element?(view, "#employee-type-edit-#{system_type.id}")

    assert has_element?(
             view,
             "a#employee-type-#{system_type.id}-link[href='/employee-types/#{system_type.id}']",
             system_type.label
           )
  end

  test "the edit route is retired for custom and system types alike", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)
    {:ok, types} = Employee.list_employee_types(scope, 73)
    system_type = Enum.find(types, & &1.is_system)
    {:ok, custom} = Employee.create_employee_type(scope, 73, %{code: "temp", label: "Temporary"})

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.update"])

    for type <- [system_type, custom] do
      retired = "/employee-types/#{type.id}/edit"
      assert Phoenix.Router.route_info(BilimbiWeb.Router, "GET", retired, "localhost") == :error
      assert conn |> log_in_as() |> get(retired) |> Map.fetch!(:status) == 404
    end
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
    refute has_element?(view, "#employee-type-delete-#{type.id}[phx-disable-with]")

    # Deleting confirms through the shared dialog, which leads with the
    # consequence and says what cannot be undone; no native confirm remains.
    refute has_element?(view, "#employee-type-delete-#{type.id}[data-confirm]")
    view |> element("#employee-type-delete-#{type.id}") |> render_click()

    assert_modal_dialog(
      view,
      "delete-employee-type-confirm",
      "Employee type “Temporary” will be deleted."
    )

    assert has_element?(view, "dialog#delete-employee-type-confirm[role='alertdialog']")

    assert has_element?(
             view,
             "#delete-employee-type-confirm-description",
             "It can no longer be chosen for an employee. This cannot be undone."
           )

    # Cancelling keeps the type.
    view |> element("#delete-employee-type-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(view, "#delete-employee-type-confirm")
    assert has_element?(view, "#employee-types td", "Temporary")
    assert {:ok, _} = Employee.get_employee_type(scope, 73, type.id)

    # Confirming deletes it and reports the completed write as a success.
    view |> element("#employee-type-delete-#{type.id}") |> render_click()

    assert has_element?(
             view,
             "#delete-employee-type-confirm-confirm[phx-disable-with='Deleting…']",
             "Delete"
           )

    view |> element("#delete-employee-type-confirm-confirm") |> render_click()
    refute has_element?(view, "#delete-employee-type-confirm")

    render_async(view, 5_000)

    refute has_element?(view, "#employee-types td", "Temporary")
    assert has_element?(view, "#flash-success", "Employee type deleted.")

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

    view |> element("#employee-type-delete-#{type.id}") |> render_click()

    # The reply to the confirm is the in-flight render, read before the async
    # delete can answer it: the dialog has closed and the row's own control
    # comes back busy rather than having its glyph replaced by text.
    in_flight =
      view
      |> element("#delete-employee-type-confirm-confirm")
      |> render_click()

    refute has_element?(view, "#delete-employee-type-confirm")

    busy =
      in_flight
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#employee-type-delete-#{type.id}[aria-busy='true']")

    assert Enum.count(busy) == 1

    render_async(view, 5_000)

    assert render(view) =~ "Cannot delete: employees are using this type."
    assert has_element?(view, "#employee-type-delete-#{type.id}")
    refute has_element?(view, "#employee-type-delete-#{type.id}[aria-busy]")
    assert {:ok, _} = Employee.get_employee_type(scope, 73, type.id)
  end

  test "refuses another row's delete while one is in flight", %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, running} = Employee.create_employee_type(scope, 73, %{code: "temp", label: "Temporary"})
    {:ok, other} = Employee.create_employee_type(scope, 73, %{code: "relief", label: "Relief"})

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.delete"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types")

    # The sandbox hands every process the one connection, so a transaction held
    # here pins the delete task on its first query and the delete stays in
    # flight for the whole block. Neither click needs the database: the
    # capability check and the guard both read assigns.
    Bilimbi.Base.Repo.transaction(fn ->
      view |> element("#employee-type-delete-#{running.id}") |> render_click()
      view |> element("#delete-employee-type-confirm-confirm") |> render_click()

      # Only the deleting row's own control goes busy, so another row's
      # request still reaches the server. One delete runs at a time, and the
      # operator is told this one was not served before any dialog opens,
      # rather than confirming a delete that would be dropped.
      refused =
        view
        |> element("#employee-type-delete-#{other.id}")
        |> render_click()

      assert refused =~ "Another employee type is still being deleted."
      refute has_element?(view, "#delete-employee-type-confirm")

      # The deleting row's own control is busy and disabled; a forged repeat is
      # the running request and needs nothing.
      render_click(view, "request_delete", %{"id" => to_string(running.id)})
      refute has_element?(view, "#delete-employee-type-confirm")
    end)

    render_async(view, 5_000)

    assert {:error, :type_not_found} = Employee.get_employee_type(scope, 73, running.id)
    assert {:ok, _} = Employee.get_employee_type(scope, 73, other.id)

    # The refusal was for that moment only: once nothing is in flight the same
    # row deletes.
    view |> element("#employee-type-delete-#{other.id}") |> render_click()
    view |> element("#delete-employee-type-confirm-confirm") |> render_click()

    render_async(view, 5_000)

    assert {:error, :type_not_found} = Employee.get_employee_type(scope, 73, other.id)
  end

  test "a sort patch during an in-flight delete leaves the deleting row marked busy",
       %{conn: conn} do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, type} =
      Employee.create_employee_type(scope, 73, %{code: "consultant", label: "Consultant"})

    # An in-use type fails its delete, so the row is still on the page to be
    # read after the patch instead of having been deleted out from under it.
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

    test_pid = self()

    # The sandbox hands every process the one connection, so a transaction
    # held here pins the delete task on its first query. The delete is
    # provably still in flight until this holder is released.
    holder =
      spawn_link(fn ->
        Bilimbi.Base.Repo.transaction(fn ->
          send(test_pid, :pinned)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :pinned, 5_000

    # Confirming the delete needs no database: the capability check and the
    # guard both read assigns.
    view |> element("#employee-type-delete-#{type.id}") |> render_click()
    view |> element("#delete-employee-type-confirm-confirm") |> render_click()

    # The patch a sort header pushes, driven while the delete is pinned.
    # `render_patch/2` parses no DOM, so the patch is two local message hops
    # and reaches the LiveView's mailbox well before the released task can
    # reach it across five round trips to PostgreSQL. The LiveView therefore
    # runs `handle_params` -> `load_page` with the delete still in flight,
    # which is the moment this test exists to cover; it queues for the same
    # connection behind the task and completes once the task lets go.
    patch =
      Task.async(fn ->
        send(test_pid, :patching)
        render_patch(view, ~p"/employee-types?sort=code")
      end)

    assert_receive :patching, 5_000
    send(holder, :release)

    patched = Task.await(patch, 5_000)

    # The patch did not clear the delete marker: the row the operator is
    # deleting still says so, so the guard that stops a second confirmed
    # delete from overwriting this one under the same async name is still
    # armed while the page is being re-sorted.
    busy =
      patched
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#employee-type-delete-#{type.id}[aria-busy='true']")

    assert Enum.count(busy) == 1

    render_async(view, 5_000)

    # That first delete's own outcome still reaches the operator, and the row
    # goes idle once it resolves.
    assert render(view) =~ "Cannot delete: employees are using this type."
    refute has_element?(view, "#employee-type-delete-#{type.id}[aria-busy]")
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
    view |> element("#delete-employee-type-confirm-confirm") |> render_click()

    render_async(view, 5_000)

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
