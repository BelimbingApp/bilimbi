defmodule BilimbiWeb.EmployeeShowAddressesTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Employee

  setup do
    signed_in_identity!()
    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-001",
        full_name: "John Doe",
        email: "john@example.test"
      })

    %{scope: scope, employee: employee}
  end

  test "the addresses panel is the shared table with in-place priority and a demoted unlink", %{
    conn: conn,
    employee: employee
  } do
    {:ok, scope} = Tenancy.scope(41)

    {:ok, home} =
      Address.create_address(scope, %{label: "Home", line1: "12 Jalan Damai", locality: "Ipoh"})

    {:ok, :attached} =
      Address.attach_to_employee(scope, home.id, employee.id, %{kind: ["other"], priority: 1})

    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    # Shared heading with its count over the shared table; no hand-written table.
    assert has_element?(view, "#addresses-panel h2#employee-addresses-heading", "Addresses")
    assert has_element?(view, "#employee-addresses-heading + span", "1")
    assert has_element?(view, "#addresses-panel caption", "Employee addresses")

    assert has_element?(
             view,
             "#addresses-panel th[aria-sort='ascending'] button#addresses-table-sort-label"
           )

    assert has_element?(view, "#addresses-table-rows tr#address-row-#{home.id}")
    assert has_element?(view, "#address-link-#{home.id}[href='/addresses/#{home.id}']", "Home")
    assert has_element?(view, "#address-row-#{home.id}", "12 Jalan Damai, Ipoh")

    # Sorting reaches the panel, not the page.
    view |> element("#addresses-table-sort-priority") |> render_click()
    assert has_element?(view, "th[aria-sort='ascending'] #addresses-table-sort-priority")

    # Priority commits in place through the shared editor addressed to the panel.
    assert has_element?(
             view,
             "#address-priority-#{home.id}[phx-hook='InlineEdit'][data-save-event='save_address_priority']"
           )

    view
    |> element("#address-priority-#{home.id}")
    |> render_hook("save_address_priority", %{"id" => to_string(home.id), "priority" => "4"})

    assert has_element?(
             view,
             "#addresses-panel-notice[role='status'][data-kind='success']",
             "Address setting updated."
           )

    assert has_element?(view, "#address-priority-#{home.id} [data-role='text']", "4")

    {:ok, [attached]} = Address.list_employee_attached_addresses(scope, employee.id)
    assert attached.priority == 4

    # Unlinking is a demoted icon action confirmed through the shared dialog,
    # which leads with the consequence; the empty state then says what to do.
    assert has_element?(
             view,
             "button#unlink-address-#{home.id}[aria-label='Unlink address'] .hero-link-slash"
           )

    refute has_element?(view, "#unlink-address-#{home.id}[data-confirm]")

    view |> element("#unlink-address-#{home.id}") |> render_click()

    assert_modal_dialog(
      view,
      "unlink-address-confirm",
      "“Home” will be unlinked from this employee."
    )

    assert has_element?(
             view,
             "#unlink-address-confirm-description",
             "The address itself is kept and can be attached again."
           )

    view |> element("#unlink-address-confirm-cancel", "Cancel") |> render_click()
    refute has_element?(view, "#unlink-address-confirm")
    assert has_element?(view, "#address-row-#{home.id}")

    view |> element("#unlink-address-#{home.id}") |> render_click()
    view |> element("#unlink-address-confirm-confirm", "Unlink") |> render_click()

    refute has_element?(view, "#unlink-address-confirm")
    refute has_element?(view, "#address-row-#{home.id}")

    assert has_element?(
             view,
             "#addresses-panel-notice[role='status'][data-kind='success']",
             "Address unlinked."
           )

    assert {:ok, _home} = Address.get_address(scope, home.id)
    assert has_element?(view, "#addresses-table-empty", "No addresses linked.")

    assert has_element?(
             view,
             "#addresses-table-empty",
             "Attach one of the company's addresses to this employee."
           )
  end

  test "unlinking an address whose link is already gone informs rather than refuses", %{
    conn: conn,
    employee: employee
  } do
    {:ok, scope} = Tenancy.scope(41)
    {:ok, home} = Address.create_address(scope, %{label: "Home", line1: "12 Jalan Damai"})
    {:ok, flat} = Address.create_address(scope, %{label: "Flat", line1: "4 Jalan Seri"})
    {:ok, :attached} = Address.attach_to_employee(scope, home.id, employee.id)
    {:ok, :attached} = Address.attach_to_employee(scope, flat.id, employee.id)

    grant_capabilities!(["admin.employee.view", "admin.employee.update"])

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    # Another operator unlinks the address while this list still shows it:
    # the confirmation runs against a link that is already gone.
    :ok = Address.detach_from_employee(scope, home.id, employee.id)
    view |> element("#unlink-address-#{home.id}") |> render_click()
    view |> element("#unlink-address-confirm-confirm", "Unlink") |> render_click()

    refute has_element?(view, "#unlink-address-confirm")
    refute has_element?(view, "#address-row-#{home.id}")

    assert has_element?(
             view,
             "#addresses-panel-notice[role='status'][data-kind='info']",
             "That address is no longer linked."
           )

    # A request naming an address the refreshed list no longer holds.
    view |> element("#unlink-address-#{flat.id}") |> render_click(%{"id" => "#{home.id}"})

    refute has_element?(view, "#unlink-address-confirm")

    assert has_element?(
             view,
             "#addresses-panel-notice[role='status'][data-kind='info']",
             "That address is no longer linked."
           )
  end
end
