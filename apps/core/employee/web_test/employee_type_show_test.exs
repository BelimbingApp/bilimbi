defmodule BilimbiWeb.EmployeeTypeShowTest do
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
    {:ok, scope} = Tenancy.scope(41)

    {:ok, type} =
      Employee.create_employee_type(scope, 73, %{
        code: "temp_contractor",
        label: "Temporary Contractor"
      })

    %{scope: scope, type: type}
  end

  test "requires authentication", %{conn: conn, type: type} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/employee-types/#{type.id}")
  end

  test "redirects away when the actor lacks admin.employee-type.list", %{conn: conn, type: type} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn |> log_in_as() |> live(~p"/employee-types/#{type.id}")
  end

  test "a viewer without admin.employee-type.update sees the facts and no editors", %{
    conn: conn,
    type: type
  } do
    # `admin.employee.list` as well, so the Employees branch that carries the
    # Employee Types nav item renders and its highlight can be read.
    grant_capabilities!(["admin.employee.list", "admin.employee-type.list"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types/#{type.id}")

    # The record reads as facts on the shared list at the detail width, with
    # the demoted "← Back" link and no button in the header.
    assert has_element?(view, "h1", "Temporary Contractor")
    assert has_element?(view, "#employee-type-show-page.max-w-7xl")
    assert has_element?(view, "#employee-type-view-code", "temp_contractor")
    assert has_element?(view, "#employee-type-view-label", "Temporary Contractor")
    assert has_element?(view, "#employee-type-view-kind", "custom")
    assert has_element?(view, "#nav-admin-employee-type[aria-current='page']")

    assert has_element?(
             view,
             "a#employee-type-back[href='/employee-types'][title='Back to employee types']",
             "Back"
           )

    refute has_element?(view, "main header button")
    refute has_element?(view, "[phx-hook='InlineEdit']")
    refute has_element?(view, "#employee-type-label")
    refute has_element?(view, "form")

    # A forged commit from a viewer writes nothing and reports the refusal.
    render_hook(view, "save_field", %{"id" => to_string(type.id), "label" => "Forged"})

    assert has_element?(
             view,
             "#flash-group",
             "You do not have permission to update employee types."
           )

    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, %{label: "Temporary Contractor"}} = Employee.get_employee_type(scope, 73, type.id)
  end

  test "saves the committed label in place and reports the outcome on that fact", %{
    conn: conn,
    scope: scope,
    type: type
  } do
    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types/#{type.id}")

    # The label is the one in-place editor; the code is permanent and reads
    # as text. The label is required, so the hook refuses an emptied input.
    assert has_element?(
             view,
             "#employee-type-label[phx-hook='InlineEdit'][data-save-event='save_field']"
           )

    refute has_element?(view, "#employee-type-label[data-allow-empty]")
    refute has_element?(view, "#employee-type-view-code [phx-hook='InlineEdit']")
    refute has_element?(view, "#employee-type-form")
    refute has_element?(view, "#employee-type-save")
    refute has_element?(view, "main header button")

    # A committed edit saves by itself; the title follows and nothing flashes.
    render_hook(view, "save_field", %{
      "id" => to_string(type.id),
      "label" => "  Independent Contractor  "
    })

    assert has_element?(view, "h1", "Independent Contractor")
    assert has_element?(view, "#employee-type-view-label", "Independent Contractor")
    assert has_element?(view, "#employee-type-label-status[role='status']", "Saved")
    assert page_title(view) == "Independent Contractor"
    refute has_element?(view, "#flash-group", "updated")

    assert {:ok, %{label: "Independent Contractor", code: "temp_contractor"}} =
             Employee.get_employee_type(scope, 73, type.id)

    # The list reads the saved label.
    {:ok, index, _html} = conn |> log_in_as() |> live(~p"/employee-types")
    assert has_element?(index, "#employee-types td", "Independent Contractor")

    # A field the page does not edit is ignored, not written.
    render_hook(view, "save_field", %{"id" => to_string(type.id), "code" => "forged"})
    assert {:ok, %{code: "temp_contractor"}} = Employee.get_employee_type(scope, 73, type.id)
  end

  test "a refused commit keeps the stored value on screen and reports the reason on the fact", %{
    conn: conn,
    scope: scope,
    type: type
  } do
    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types/#{type.id}")

    # A forged blank is refused by the domain, on the fact, with no flash.
    render_hook(view, "save_field", %{"id" => to_string(type.id), "label" => "   "})

    assert has_element?(view, "#employee-type-label-status[role='alert']", "was not saved")
    assert has_element?(view, "#employee-type-label-status", "Label can't be blank")
    assert has_element?(view, "#employee-type-view-label", "Temporary Contractor")
    assert has_element?(view, "#employee-type-label input[aria-invalid='true']")
    assert has_element?(view, "h1", "Temporary Contractor")
    refute has_element?(view, "#employee-type-label-status", "Saved")
    refute has_element?(view, "#flash-group", "was not saved")
    assert {:ok, %{label: "Temporary Contractor"}} = Employee.get_employee_type(scope, 73, type.id)

    # An overlong label is refused with its reason and the rejected value
    # truncated to what identifies it.
    long = String.duplicate("x", 256)
    render_hook(view, "save_field", %{"id" => to_string(type.id), "label" => long})

    assert has_element?(
             view,
             "#employee-type-label-status[role='alert']",
             "Label should be at most 255 character(s)"
           )

    assert has_element?(view, "#employee-type-label-status", String.duplicate("x", 60) <> "…")
    refute has_element?(view, "#employee-type-label-status", String.duplicate("x", 61))

    # The alert clears only when the fact is committed again, and lands.
    render_hook(view, "save_field", %{"id" => to_string(type.id), "label" => "Relief"})

    refute has_element?(view, "#employee-type-label-status[role='alert']")
    assert has_element?(view, "#employee-type-label-status", "Saved")
    assert {:ok, %{label: "Relief"}} = Employee.get_employee_type(scope, 73, type.id)
  end

  test "a system type reads as facts for everyone and refuses a forged commit on the fact", %{
    conn: conn,
    scope: scope
  } do
    {:ok, types} = Employee.list_employee_types(scope, 73)
    system_type = Enum.find(types, & &1.is_system)

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types/#{system_type.id}")

    assert has_element?(view, "#employee-type-view-code", system_type.code)
    assert has_element?(view, "#employee-type-view-label", system_type.label)
    assert has_element?(view, "#employee-type-view-kind", "system")
    assert has_element?(view, "#employee-type-details-card", "cannot be edited")
    refute has_element?(view, "[phx-hook='InlineEdit']")

    render_hook(view, "save_field", %{"id" => to_string(system_type.id), "label" => "Forged"})

    assert has_element?(
             view,
             "#employee-type-view-label",
             "System employee types cannot be edited."
           )

    assert {:ok, %{label: label}} = Employee.get_employee_type(scope, 73, system_type.id)
    assert label == system_type.label
  end

  test "a type outside the company or an invalid id returns to the list", %{conn: conn} do
    CompanyFixtures.insert_company!(%{id: 74, tenant_id: 41, code: "sibling_corp"})
    {:ok, scope} = Tenancy.scope(41)
    {:ok, foreign} = Employee.create_employee_type(scope, 74, %{code: "theirs", label: "Theirs"})

    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.update"])

    for path <- [~p"/employee-types/#{foreign.id}", "/employee-types/0", "/employee-types/abc"] do
      assert {:error,
              {:live_redirect,
               %{
                 to: "/employee-types",
                 flash: %{"error" => "That employee type does not exist in this company."}
               }}} = conn |> log_in_as() |> live(path)
    end
  end

  test "a write forged after grant revocation changes nothing", %{
    conn: conn,
    scope: scope,
    type: type
  } do
    grant_capabilities!(["admin.employee-type.list", "admin.employee-type.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employee-types/#{type.id}")

    # A commit that did land, so the refusal below has a stale "Saved" to clear.
    render_hook(view, "save_field", %{"id" => to_string(type.id), "label" => "Relief"})
    assert has_element?(view, "#employee-type-label-status[role='status']", "Saved")

    grant =
      Bilimbi.Base.Authz.list_principal_capabilities(scope, page_size: 100)
      |> Map.fetch!(:entries)
      |> Enum.find(&(&1.capability == "admin.employee-type.update"))

    assert {:ok, :removed} = Bilimbi.Base.Authz.remove_principal_capability(scope, grant.id)

    render_hook(view, "save_field", %{"id" => to_string(type.id), "label" => "Forged"})

    assert has_element?(
             view,
             "#flash-group",
             "You do not have permission to update employee types."
           )

    refute has_element?(view, "#employee-type-label-status")
    assert {:ok, %{label: "Relief"}} = Employee.get_employee_type(scope, 73, type.id)
  end
end
