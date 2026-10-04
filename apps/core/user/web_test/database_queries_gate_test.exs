defmodule BilimbiWeb.DatabaseQueriesGateTest do
  use BilimbiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()
    UserFixtures.create_user_database_queries_table!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})

    UserFixtures.insert_user!(%{
      id: 91,
      company_id: 73,
      name: "Ada Lovelace",
      email: "ada@example.com"
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 73,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    {:ok, scope} = Tenancy.scope(41)

    %{scope: scope}
  end

  describe "operator-only gate (#650)" do
    setup do
      # A second tenant that is NOT the platform operator, with its own company
      # and user, so the console can be probed by a fully-capable non-operator.
      CompanyFixtures.insert_tenant!(%{
        id: 51,
        name: "Ordinary tenant",
        is_platform_operator: false
      })

      CompanyFixtures.insert_company!(%{
        id: 83,
        tenant_id: 51,
        name: "Ordinary Co",
        code: "ordinary_co"
      })

      UserFixtures.insert_user!(%{
        id: 95,
        company_id: 83,
        name: "Nadia Non-Operator",
        email: "nadia@example.com"
      })

      # Grant BOTH capabilities to the non-operator so the capability gate passes
      # and any refusal is isolated to the platform-operator tenant gate.
      grant_capabilities!(
        ["admin.system.database-table.list", "admin.system.database-table.edit"],
        tenant_id: 51,
        company_id: 83,
        user_id: 95
      )

      %{non_operator: session_user(%{"user_id" => 95, "company_id" => 83})}
    end

    test "a fully-capable non-operator is refused at the Index mount", %{
      conn: conn,
      non_operator: non_operator
    } do
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn |> log_in_as(non_operator) |> live(~p"/admin/system/database-queries")
    end

    test "a fully-capable non-operator is refused at the Show mount", %{
      conn: conn,
      non_operator: non_operator
    } do
      # The gate halts in on_mount, before the slug is ever looked up.
      assert {:error, {:redirect, %{to: "/dashboard"}}} =
               conn
               |> log_in_as(non_operator)
               |> live(~p"/admin/system/database-queries/any-query")
    end

    test "the executor fails closed on a forged execute, before touching the store" do
      # A query that would raise at the database if the guard ever let it run.
      sql = "SELECT * FROM __blb_absent_table_650"

      # Absent opt fails closed with the operator error — never a DB error, so
      # the store was not reached.
      assert {:error, msg} = Database.execute_readonly(sql, %{}, [])
      assert msg =~ "platform operator"

      # Explicit false is identical.
      assert {:error, ^msg} = Database.execute_readonly(sql, %{}, operator: false)

      # With the operator tenant asserted, the guard passes and the store IS
      # reached — proven by the error now coming from Postgres, not the gate.
      assert {:error, db_msg} = Database.execute_readonly(sql, %{}, operator: true)
      refute db_msg =~ "platform operator"
      assert db_msg =~ "does not exist"
    end
  end
end
