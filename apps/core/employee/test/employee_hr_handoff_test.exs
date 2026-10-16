defmodule Bilimbi.Core.EmployeeHrHandoffTest do
  @moduledoc """
  The reads the owner of employment facts claims Core's legacy HR rows with:
  the batch person mapping and the tenant-wide, archived-inclusive handoff
  page. Both stay inside the tenant and write nothing.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.Employee.HrHandoffEntry
  alias Bilimbi.Core.Employee.HrHandoffPage

  import Bilimbi.Core.Employee.TestFixtures

  setup do
    create_employee_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41, name: "Tenant A"})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41, name: "Live", code: "live"})
    CompanyFixtures.insert_company!(%{id: 74, tenant_id: 41, name: "Archived", code: "archived"})
    CompanyFixtures.insert_tenant!(%{id: 42, name: "Tenant B", is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 75, tenant_id: 42, name: "Other", code: "other"})
    :ok = Employee.ensure_system_types()

    {:ok, scope} = Tenancy.scope(41)
    {:ok, other} = Tenancy.scope(42)

    {:ok, staff} =
      Employee.create_employee(scope, 73, %{
        employee_number: "E-1",
        full_name: "Sam Staff",
        status: "probation",
        employment_start: "2025-03-01",
        metadata: %{"grade" => "B"}
      })

    {:ok, agent} =
      Employee.create_employee(scope, 73, %{
        employee_number: "A-1",
        full_name: "Ada Agent",
        employee_type: "agent"
      })

    {:ok, leaver} =
      Employee.create_employee(scope, 74, %{
        employee_number: "E-9",
        full_name: "Lee Leaver",
        status: "terminated",
        employment_end: "2026-01-31"
      })

    archive_company!(74)

    {:ok, foreign} =
      Employee.create_employee(other, 75, %{employee_number: "F-1", full_name: "F"})

    %{
      scope: scope,
      other: other,
      staff: staff,
      agent: agent,
      leaver: leaver,
      foreign: foreign,
      unmapped: insert_unmapped_employee!(73)
    }
  end

  describe "person_identities/2" do
    test "maps many employees in one call, archived companies included, others omitted", ctx do
      ids = [ctx.staff.id, ctx.agent.id, ctx.leaver.id, ctx.foreign.id, ctx.unmapped, 999_999]

      assert {:ok, identities} = Employee.person_identities(ctx.scope, ids)

      assert identities |> Map.keys() |> Enum.sort() == [
               ctx.staff.id,
               ctx.agent.id,
               ctx.leaver.id
             ]

      for employee <- [ctx.staff, ctx.agent, ctx.leaver] do
        assert {:ok, single} = Employee.person_identity(ctx.scope, employee.id)

        assert identities[employee.id] == %{
                 person_id: single.person_id,
                 affiliation_id: single.affiliation_id,
                 company_id: employee.company_id
               }
      end

      assert {:ok, %{}} = Employee.person_identities(ctx.scope, [])
      assert {:ok, foreign} = Employee.person_identities(ctx.other, ids)
      assert Map.keys(foreign) == [ctx.foreign.id]
    end

    test "reads in a fixed number of queries whatever the batch size", ctx do
      ids = [ctx.staff.id, ctx.agent.id, ctx.leaver.id]

      one = count_queries(fn -> Employee.person_identities(ctx.scope, Enum.take(ids, 1)) end)
      assert one > 0
      assert count_queries(fn -> Employee.person_identities(ctx.scope, ids) end) == one
    end

    test "refuses more than 1,000 IDs or IDs that are not positive integers", ctx do
      assert {:ok, _} = Employee.person_identities(ctx.scope, Enum.to_list(1..1_000))

      assert {:error, :invalid_options} =
               Employee.person_identities(ctx.scope, Enum.to_list(1..1_001))

      assert {:error, :invalid_options} = Employee.person_identities(ctx.scope, [ctx.staff.id, 0])
      assert {:error, :invalid_options} = Employee.person_identities(ctx.scope, ["1"])
      assert {:error, :invalid_options} = Employee.person_identities(ctx.scope, nil)
    end
  end

  describe "hr_handoff_page/3" do
    test "pages every retained row of the tenant, archived company and agents included", ctx do
      assert {:ok, %HrHandoffPage{entries: first, next_cursor: cursor}} =
               Employee.hr_handoff_page(ctx.scope, nil, limit: 3)

      assert is_integer(cursor)

      assert {:ok, %HrHandoffPage{entries: rest, next_cursor: nil}} =
               Employee.hr_handoff_page(ctx.scope, cursor, limit: 3)

      entries = first ++ rest

      assert Enum.map(entries, & &1.employee_id) ==
               Enum.sort([ctx.staff.id, ctx.agent.id, ctx.leaver.id, ctx.unmapped])

      by_id = Map.new(entries, &{&1.employee_id, &1})
      {:ok, staff_identity} = Employee.person_identity(ctx.scope, ctx.staff.id)

      assert %HrHandoffEntry{
               company_id: 73,
               employee_number: "E-1",
               employee_type: "full_time",
               status: "probation",
               employment_start: ~D[2025-03-01],
               employment_end: nil,
               metadata: %{"grade" => "B"},
               created_at: %NaiveDateTime{},
               updated_at: %NaiveDateTime{}
             } = by_id[ctx.staff.id]

      assert {by_id[ctx.staff.id].person_id, by_id[ctx.staff.id].affiliation_id} ==
               {staff_identity.person_id, staff_identity.affiliation_id}

      assert %HrHandoffEntry{employee_type: "agent"} = by_id[ctx.agent.id]

      assert %HrHandoffEntry{
               company_id: 74,
               status: "terminated",
               employment_end: ~D[2026-01-31],
               person_id: person_id
             } = by_id[ctx.leaver.id]

      assert is_integer(person_id)

      assert %HrHandoffEntry{employee_number: "U-1", person_id: nil, affiliation_id: nil} =
               by_id[ctx.unmapped]

      assert {:ok, %HrHandoffPage{entries: [foreign], next_cursor: nil}} =
               Employee.hr_handoff_page(ctx.other, nil)

      assert foreign.employee_id == ctx.foreign.id
    end

    test "writes nothing", ctx do
      before = Repo.all(from(e in "employees", select: {e.id, e.updated_at}, order_by: e.id))
      {:ok, _page} = Employee.hr_handoff_page(ctx.scope, nil)

      assert Repo.all(from(e in "employees", select: {e.id, e.updated_at}, order_by: e.id)) ==
               before
    end

    test "refuses a bad cursor or page size", ctx do
      assert {:error, :invalid_options} = Employee.hr_handoff_page(ctx.scope, 0)
      assert {:error, :invalid_options} = Employee.hr_handoff_page(ctx.scope, "1")
      assert {:error, :invalid_options} = Employee.hr_handoff_page(ctx.scope, nil, limit: 1_001)
      assert {:error, :invalid_options} = Employee.hr_handoff_page(ctx.scope, nil, limit: 0)
      assert {:ok, %HrHandoffPage{}} = Employee.hr_handoff_page(ctx.scope, nil, limit: 1_000)
    end
  end

  defp archive_company!(id) do
    Ecto.Adapters.SQL.query!(
      Repo,
      "UPDATE companies SET status = 'archived', deleted_at = now() WHERE id = $1",
      [id]
    )
  end

  defp insert_unmapped_employee!(company_id) do
    %{rows: [[id]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        INSERT INTO employees (company_id, employee_number, full_name)
        VALUES ($1, 'U-1', 'Una Unmapped')
        RETURNING id
        """,
        [company_id]
      )

    id
  end

  defp count_queries(fun) do
    handler = {__MODULE__, make_ref()}
    parent = self()

    :telemetry.attach(
      handler,
      [:bilimbi, :base, :repo, :query],
      fn _event, _measurements, _metadata, _config ->
        if self() == parent, do: send(parent, {handler, :query})
      end,
      nil
    )

    try do
      {:ok, _} = fun.()
      drain(handler, 0)
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(handler, count) do
    receive do
      {^handler, :query} -> drain(handler, count + 1)
    after
      0 -> count
    end
  end
end
