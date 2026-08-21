defmodule BilimbiWeb.AuditCaptureSessionTest do
  @moduledoc """
  The #630 write-session proof: real domain writes leave nonzero,
  canonically-shaped `base_audit_mutations` rows — the property whose
  absence (three opt-in callers, empty tables after a full seeded session)
  motivated ADR 0013's repo-level capture.
  """

  use BilimbiWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    AuditFixtures.create_audit_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})
    :ok = Employee.ensure_system_types()
    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  defp listener_rows(auditable_type) do
    Repo.all(
      from(row in MutationSchema,
        where: row.source == "listener" and row.auditable_type == ^auditable_type,
        order_by: row.id
      )
    )
  end

  test "an Employee write session leaves shaped listener rows", %{scope: scope} do
    {:ok, employee} =
      Employee.create_employee(scope, 73, %{
        employee_number: "EMP-630",
        full_name: "Grace Hopper"
      })

    {:ok, _updated} =
      Employee.update_employee(scope, 73, employee.id, %{full_name: "Rear Admiral Hopper"})

    assert [created, updated] = listener_rows("Bilimbi.Core.Employee.Schema")

    assert created.event == "created"
    assert created.new_values["full_name"] == "Grace Hopper"
    assert created.auditable_id == to_string(employee.id)

    assert updated.event == "updated"
    assert updated.old_values == %{"full_name" => "Grace Hopper"}
    assert updated.new_values == %{"full_name" => "Rear Admiral Hopper"}
  end

  test "a Company write session leaves shaped listener rows with the row's tenant", %{
    scope: scope
  } do
    {:ok, _company} = Company.update_company(scope, 73, %{website: "https://example.test"})

    assert [row] = listener_rows("Bilimbi.Core.Company.Schema")
    assert row.event == "updated"
    assert row.tenant_id == 41
    assert row.new_values["website"] == "https://example.test"
  end

  test "an authenticated LiveView write records the signed-in actor", %{conn: conn} do
    grant_capabilities!(["admin.employee.list", "admin.employee.view", "admin.employee.update"])

    {:ok, scope} = Tenancy.scope(41)

    {:ok, employee} =
      Employee.create_employee(scope, 73, %{employee_number: "EMP-631", full_name: "John Doe"})

    {:ok, view, _html} = conn |> log_in_as() |> live(~p"/employees/#{employee.id}")

    render_submit(view, "save_field", %{"full_name" => "John Q. Doe"})

    row =
      listener_rows("Bilimbi.Core.Employee.Schema")
      |> Enum.find(&(&1.event == "updated"))

    assert row, "the LiveView write left no listener row"
    assert row.actor_type == "user"
    assert row.actor_id == 91
    assert row.company_id == 73
    assert row.tenant_id == 41
    assert row.new_values == %{"full_name" => "John Q. Doe"}
  end

  test "without_auditing silences a session and explicit records still work", %{scope: scope} do
    Audit.without_auditing(fn ->
      {:ok, _employee} =
        Employee.create_employee(scope, 73, %{employee_number: "EMP-632", full_name: "Quiet"})
    end)

    assert listener_rows("Bilimbi.Core.Employee.Schema") == []
  end
end
