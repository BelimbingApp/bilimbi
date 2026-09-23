defmodule BilimbiWeb.AuditImpersonationTest do
  @moduledoc """
  The audit trail tells the truth under impersonation: an action performed
  while an operator impersonates another user names both the account acted
  as (`actor_id`) and the operator who acted (`impersonator_id`), on the
  captured mutation and on the retained impersonation transition actions.
  """

  use BilimbiWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit.ActionSchema
  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  @operator_id 91
  @target_id 92
  @employee_capabilities ~w(admin.employee.list admin.employee.view admin.employee.update)

  setup do
    UserFixtures.create_user_tables!()
    UserFixtures.create_user_database_queries_table!()
    AuditFixtures.create_audit_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    UserFixtures.insert_user!(%{
      id: @operator_id,
      company_id: 73,
      name: "Admin User",
      email: "admin@example.com",
      password_hash: "not-used"
    })

    UserFixtures.insert_user!(%{
      id: @target_id,
      company_id: 73,
      name: "Target User",
      email: "target@example.com",
      password_hash: "not-used"
    })

    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{employee_number: "EMP-900", full_name: "Before"})

    grant_capabilities!(["admin.user.impersonate" | @employee_capabilities],
      user_id: @operator_id
    )

    grant_capabilities!(@employee_capabilities, user_id: @target_id)

    %{employee: employee, scope: scope}
  end

  defp employee_update_rows do
    Repo.all(
      from(row in MutationSchema,
        where:
          row.source == "listener" and row.event == "updated" and
            row.auditable_type == "Bilimbi.Core.Employee.Schema",
        order_by: row.id
      )
    )
  end

  defp action_rows(event) do
    Repo.all(from(row in ActionSchema, where: row.event == ^event, order_by: row.id))
  end

  test "an impersonated write names both the account acted as and the operator", %{
    conn: conn,
    employee: employee
  } do
    impersonating =
      conn
      |> log_in_as(%{"user_id" => @operator_id, "company_id" => 73})
      |> post(~p"/admin/impersonate/#{@target_id}")

    assert redirected_to(impersonating) == ~p"/dashboard"

    {:ok, view, _html} = live(impersonating, ~p"/employees/#{employee.id}")
    render_submit(view, "save_field", %{"full_name" => "Changed while impersonated"})

    assert [row] = employee_update_rows()
    assert row.actor_type == "user"
    # The account the change was performed as ...
    assert row.actor_id == @target_id
    # ... and the operator who actually performed it.
    assert row.impersonator_id == @operator_id
    assert row.new_values == %{"full_name" => "Changed while impersonated"}
  end

  test "an explicit action recorded while impersonating names both identities", %{
    conn: conn,
    scope: scope
  } do
    grant_capabilities!(["admin.system.database-table.list"], user_id: @target_id)

    # The console runs through its own select-only connection and sees only
    # committed state, never this sandbox's temporary tables, so the query
    # carries its own row.
    {:ok, query} =
      User.create_database_query(scope, @target_id, %{
        name: "Count users",
        description: "Borrowed session query",
        sql_query: "SELECT 1 AS n;"
      })

    impersonating =
      conn
      |> log_in_as(%{"user_id" => @operator_id, "company_id" => 73})
      |> post(~p"/admin/impersonate/#{@target_id}")

    {:ok, view, _html} = live(impersonating, ~p"/admin/system/database-queries/#{query.slug}")
    view |> element("#btn-run-query") |> render_click()

    # The screen executes on mount and again on the click; every execution
    # in the borrowed session names both identities.
    rows = action_rows("database_query.executed")
    assert rows != []

    for row <- rows do
      assert row.actor_type == "user"
      assert row.actor_id == @target_id
      assert row.impersonator_id == @operator_id
      assert row.payload["name"] == "Count users"
    end
  end

  test "starting and stopping impersonation are retained actions by the operator", %{
    conn: conn
  } do
    impersonating =
      conn
      |> log_in_as(%{"user_id" => @operator_id, "company_id" => 73})
      |> post(~p"/admin/impersonate/#{@target_id}")

    assert redirected_to(impersonating) == ~p"/dashboard"

    assert [started] = action_rows("impersonation.started")
    assert started.actor_type == "user"
    assert started.actor_id == @operator_id
    assert started.impersonator_id == nil
    assert started.company_id == 73
    assert started.tenant_id == 41
    assert started.is_retained
    assert started.payload["summary"] == "Started impersonating Target User"

    assert started.payload["subject"] == %{
             "name" => "user",
             "id" => @target_id,
             "label" => "User#92"
           }

    assert started.payload["context"] == %{
             "impersonator_id" => @operator_id,
             "target_id" => @target_id
           }

    left = post(impersonating, ~p"/admin/impersonate/leave")
    assert redirected_to(left) == ~p"/dashboard"

    assert [stopped] = action_rows("impersonation.stopped")
    assert stopped.actor_id == @operator_id
    assert stopped.impersonator_id == nil
    assert stopped.is_retained

    assert stopped.payload["context"] == %{
             "impersonator_id" => @operator_id,
             "target_id" => @target_id
           }
  end

  test "a write after leaving impersonation names no operator", %{
    conn: conn,
    employee: employee
  } do
    left =
      conn
      |> log_in_as(%{"user_id" => @operator_id, "company_id" => 73})
      |> post(~p"/admin/impersonate/#{@target_id}")
      |> post(~p"/admin/impersonate/leave")

    assert redirected_to(left) == ~p"/dashboard"

    {:ok, view, _html} = live(left, ~p"/employees/#{employee.id}")
    render_submit(view, "save_field", %{"full_name" => "Changed as myself"})

    assert [row] = employee_update_rows()
    assert row.actor_id == @operator_id
    assert row.impersonator_id == nil
  end
end
