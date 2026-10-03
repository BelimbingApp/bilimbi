defmodule BilimbiWeb.ComponentEventAuthorizationTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Session
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Address.TestFixtures, as: AddressFixtures
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup %{conn: conn} do
    UserFixtures.create_user_tables!()
    AddressFixtures.create_address_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73})
    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{employee_number: "COMP-1", full_name: "Grace Hopper"})

    {:ok, address} = Address.create_address(scope, %{label: "Home", line1: "12 Jalan Damai"})
    conn = log_in_as(conn, session_user(%{"session_id" => "component-authority"}))
    %{conn: conn, scope: scope, employee: employee, address: address}
  end

  for kind <- [:company, :employee],
      change <- [:page_revoked, :operation_revoked, :session_ended, :login_removed, :unchanged] do
    test "#{kind} component confirmation after #{change}", c do
      kind = unquote(kind)
      change = unquote(change)
      page = "admin.#{kind}.view"
      operation = "admin.#{kind}.update"
      grant_capabilities!(["admin.#{kind}.list", page, operation])

      {path, list} =
        case kind do
          :company ->
            assert {:ok, :attached} = Address.attach_to_company(c.scope, c.address.id, 73, %{})
            {~p"/companies/73", fn -> Address.list_company_attached_addresses(c.scope, 73) end}

          :employee ->
            assert {:ok, :attached} =
                     Address.attach_to_employee(c.scope, c.address.id, c.employee.id, %{})

            {~p"/employees/#{c.employee.id}",
             fn -> Address.list_employee_attached_addresses(c.scope, c.employee.id) end}
        end

      {:ok, view, _html} = live(c.conn, path)
      view |> element("#unlink-address-#{c.address.id}") |> render_click()
      assert has_element?(view, "#unlink-address-confirm")

      case change do
        :page_revoked ->
          assert {:ok, :stored} =
                   Authz.put_principal_capability(c.scope, 73, :user, 91, page, false)

        :operation_revoked ->
          assert {:ok, :stored} =
                   Authz.put_principal_capability(c.scope, 73, :user, 91, operation, false)

        :session_ended ->
          assert {:ok, :terminated} = Session.terminate_session("component-authority", "other")

        :login_removed ->
          assert :ok = User.delete_user(c.scope, 73, 91)

        :unchanged ->
          :ok
      end

      result = view |> element("#unlink-address-confirm-confirm") |> render_click()

      case change do
        :page_revoked ->
          assert {:error, {:redirect, %{to: "/dashboard"}}} = result

          assert assert_redirect(view, "/dashboard")["error"] ==
                   BilimbiWeb.RouteAccess.revoked_message()

        ended when ended in [:session_ended, :login_removed] ->
          assert {:error, {:redirect, %{to: "/"}}} = result
          assert assert_redirect(view, "/")["session_expired"] == "expired"

        _ ->
          assert is_binary(result)
      end

      assert {:ok, attached} = list.()
      assert Enum.any?(attached, &(&1.id == c.address.id)) == (change != :unchanged)
    end
  end
end
