defmodule Bilimbi.Base.Audit.ConsoleCaptureTest do
  @moduledoc """
  Every database console command is one audit action naming who ran it,
  from where, and what became of it — and never what it returned.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  import Ecto.Query

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.ActionSchema
  alias Bilimbi.Base.Audit.Context
  alias Bilimbi.Base.Audit.PayloadText
  alias Bilimbi.Base.Database
  alias Bilimbi.Base.Tenancy

  import Bilimbi.Base.Audit.TestFixtures
  import Bilimbi.Base.Tenancy.TestFixtures

  @context %Context{
    actor_type: "user",
    actor_id: 91,
    actor_role: "owner",
    impersonator_id: 7,
    company_id: 73,
    tenant_id: 41,
    ip_address: "203.0.113.9",
    url: "https://bilimbi.test/admin/system/database-queries/needles",
    user_agent: String.duplicate("Mozilla/5.0 ", 10),
    trace_id: "trace-id-longer-than-twelve"
  }

  setup do
    create_tenants_table!()
    create_audit_tables!()
    insert_tenant!(%{id: 41})
    Context.put(@context)
    on_exit(fn -> Context.put(nil) end)
    :ok
  end

  defp console_rows do
    Repo.all(
      from(row in ActionSchema,
        where: like(row.event, "database\\_query.%"),
        order_by: [asc: row.id]
      )
    )
  end

  defp run(sql, opts \\ []) do
    Database.execute_readonly(sql, %{}, Keyword.merge([operator: true], opts))
  end

  test "a succeeded command is one row naming the actor, the client, the text, and the count" do
    sql = "SELECT 'needle' AS n UNION ALL SELECT 'needle'"

    assert {:ok, %{total: 2}} = run(sql, name: "Needles")

    assert [row] = console_rows()
    assert row.event == "database_query.executed"
    assert row.actor_type == "user"
    assert row.actor_id == 91
    assert row.actor_role == "owner"
    assert row.impersonator_id == 7
    assert row.company_id == 73
    assert row.tenant_id == 41
    assert row.ip_address == %Postgrex.INET{address: {203, 0, 113, 9}}
    assert row.url == @context.url
    assert row.user_agent == String.slice(@context.user_agent, 0, 80)
    assert row.trace_id == "trace-id-lon"
    assert row.is_retained == false
    assert %NaiveDateTime{} = row.occurred_at

    assert row.payload == %{
             "sql" => sql,
             "name" => "Needles",
             "result" => "succeeded",
             "row_count" => 2
           }

    # The scoped read model sees the same row.
    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, [%Audit.Action{event: "database_query.executed"}]} = Audit.list_actions(scope)
  end

  test "result rows never reach the record" do
    # The value only exists in the result, not in the text that was typed.
    needle = String.duplicate("z", 40)
    assert {:ok, %{rows: [%{"secret" => ^needle}]}} = run("SELECT repeat('z', 40) AS secret")

    assert [row] = console_rows()
    refute inspect(row.payload) =~ needle
  end

  test "a refused command is one row naming the guard and its message" do
    assert {:error, message} = run("SELECT 1; DELETE FROM users")

    assert [row] = console_rows()
    assert row.event == "database_query.refused"
    assert row.actor_id == 91

    assert row.payload == %{
             "sql" => "SELECT 1; DELETE FROM users",
             "result" => "refused",
             "guard" => "keyword",
             "message" => message
           }
  end

  test "a write PostgreSQL refuses is recorded as refused by the read-only transaction" do
    Repo.query!("CREATE SEQUENCE __blb_console_audit_probe START 1")

    assert {:error, message} = run("SELECT setval('__blb_console_audit_probe', 42)")
    assert message =~ "read-only transaction"

    assert [row] = console_rows()
    assert row.event == "database_query.refused"
    assert row.payload["guard"] == "read_only_transaction"
    assert row.payload["message"] == message
  end

  test "a failed command is one row carrying the database's error message" do
    assert {:error, message} = run("SELECT * FROM __blb_absent_console_table")
    assert message =~ "does not exist"

    assert [row] = console_rows()
    assert row.event == "database_query.failed"
    assert row.actor_id == 91

    assert row.payload == %{
             "sql" => "SELECT * FROM __blb_absent_console_table",
             "result" => "failed",
             "message" => message
           }
  end

  test "a command that raises is still exactly one failed row" do
    sql = "SELECT :id::int AS id"

    assert_raise DBConnection.EncodeError, fn ->
      Database.execute_readonly(sql, %{"id" => "abc"}, operator: true)
    end

    assert [row] = console_rows()
    assert row.event == "database_query.failed"
    assert row.actor_id == 91
    assert row.payload["sql"] == sql
    assert row.payload["result"] == "failed"
    assert row.payload["message"] =~ "abc"
  end

  test "a command whose text carries a NUL is recorded with its text stored" do
    sql = "DELETE FROM users\u0000"

    assert {:error, _message} = run(sql)

    assert [row] = console_rows()
    assert row.event == "database_query.refused"
    assert row.payload["guard"] == "statement"
    assert row.payload["sql"] == "DELETE FROM users\u2400"
  end

  test "every command is its own row, refused and failed ones included" do
    assert {:ok, _} = run("SELECT 1")
    assert {:error, _} = run("DELETE FROM users")
    assert {:error, _} = run("SELECT * FROM __blb_absent_console_table")
    assert {:ok, _} = run("SELECT 2")

    assert [
             "database_query.executed",
             "database_query.refused",
             "database_query.failed",
             "database_query.executed"
           ] = Enum.map(console_rows(), & &1.event)
  end

  test "a missing actor records the guest default, never nothing" do
    Context.put(nil)

    assert {:ok, _} = run("SELECT 1")

    assert [row] = console_rows()
    assert row.actor_type == "guest"
    assert row.actor_id == 0
    assert row.tenant_id == nil
    assert row.ip_address == nil
    assert row.payload["result"] == "succeeded"
  end

  test "the text is stored as typed, bounded like every other audited string" do
    padding = String.duplicate("x", PayloadText.limit() + 500)
    sql = "SELECT 'p@ssw0rd-in-a-literal' AS leak, '#{padding}' AS padding"

    assert {:ok, _} = run(sql)

    assert [row] = console_rows()
    assert row.payload["sql"] == PayloadText.bounded(sql)
    assert String.starts_with?(row.payload["sql"], "SELECT 'p@ssw0rd-in-a-literal'")
    assert String.ends_with?(row.payload["sql"], "[truncated #{String.length(sql)} chars]")
  end

  test "the action row is not itself captured as a mutation" do
    assert {:ok, _} = run("SELECT 1")
    assert [_row] = console_rows()

    {:ok, scope} = Tenancy.scope(41)
    assert {:ok, []} = Audit.list_mutations(scope)
  end
end
