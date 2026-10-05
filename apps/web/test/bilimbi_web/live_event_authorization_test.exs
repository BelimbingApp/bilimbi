defmodule BilimbiWeb.LiveEventAuthorizationTest do
  @moduledoc """
  A page opened under a route capability stops acting when that grant is
  revoked, before its own handler runs. The security review of the People
  domain found open pages writing after revocation because the route
  capability was checked only at mount; `BilimbiWeb.RouteAccess` now re-asks
  before every event and live navigation. These drive real module pages
  through the discovered host routes.
  """

  use BilimbiWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Employee
  alias BilimbiWeb.RouteAccess

  @route_capability "admin.employee.view"

  setup %{conn: conn} do
    signed_in_identity!()
    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{employee_number: "EMP-900", full_name: "Grace Hopper"})

    grant_capabilities!(["admin.employee.list", @route_capability, "admin.employee.update"])

    %{conn: log_in_as(conn), scope: scope, employee: employee}
  end

  defp revoke!(scope, capability) do
    {:ok, :stored} = Authz.put_principal_capability(scope, 73, :user, 91, capability, false)
  end

  defp employee_updates do
    Repo.all(
      from(row in MutationSchema,
        where:
          row.source == "listener" and row.auditable_type == "Bilimbi.Core.Employee.Schema" and
            row.event == "updated"
      )
    )
  end

  defp decisions(capability) do
    Repo.aggregate(from(log in DecisionLog, where: log.capability == ^capability), :count)
  end

  test "a revoked route grant refuses the next event and writes nothing", c do
    {:ok, view, _html} = live(c.conn, ~p"/employees/#{c.employee.id}")

    revoke!(c.scope, @route_capability)

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             render_submit(view, "save_field", %{"full_name" => "After revocation"})

    flash = assert_redirect(view, "/dashboard")
    assert flash["error"] == RouteAccess.revoked_message()

    assert {:ok, %{full_name: "Grace Hopper"}} =
             Employee.get_employee(c.scope, 73, c.employee.id)

    assert employee_updates() == []
  end

  test "a revoked route grant refuses the next patch of the same page", c do
    {:ok, view, _html} = live(c.conn, ~p"/employees")

    revoke!(c.scope, "admin.employee.list")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             render_patch(view, ~p"/employees?dir=desc")

    assert assert_redirect(view, "/dashboard")["error"] == RouteAccess.revoked_message()
  end

  test "a page whose grant still holds keeps working after an unrelated revocation", c do
    {:ok, view, _html} = live(c.conn, ~p"/employees/#{c.employee.id}")

    revoke!(c.scope, "admin.employee.list")

    assert is_binary(render_submit(view, "save_field", %{"full_name" => "Rear Admiral Hopper"}))

    assert {:ok, %{full_name: "Rear Admiral Hopper"}} =
             Employee.get_employee(c.scope, 73, c.employee.id)

    assert [_updated] = employee_updates()
  end

  test "a page without a route capability keeps handling events", c do
    {:ok, view, _html} = live(c.conn, ~p"/settings/appearance")

    revoke!(c.scope, @route_capability)
    before = Repo.aggregate(DecisionLog, :count)

    assert is_binary(render_hook(view, "save", %{}))
    assert Repo.aggregate(DecisionLog, :count) == before
  end

  test "an open page costs one route decision per event and per patch", c do
    # An allowed mount answers from the in-memory capability list, so the
    # disconnected render and the connected mount write no decision row.
    # A later event and a same-route patch each re-check live.
    {:ok, view, _html} = live(c.conn, ~p"/employees")
    assert decisions("admin.employee.list") == 0

    assert is_binary(render_hook(view, "cancel_delete", %{}))
    assert decisions("admin.employee.list") == 1

    assert is_binary(render_patch(view, ~p"/employees?dir=desc"))
    assert decisions("admin.employee.list") == 2
  end
end
