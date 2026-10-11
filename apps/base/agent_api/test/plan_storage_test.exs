defmodule Bilimbi.Base.AgentApi.PlanStorageTest do
  use Bilimbi.Base.Database.DataCase, async: false
  alias Bilimbi.Base.AgentApi.{SchemaContract, TestFixtures}
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  test "owner fixture preserves the plan storage contract and PostgreSQL refuses missing tenancy" do
    Bilimbi.Base.Tenancy.TestFixtures.create_tenants_table!()
    TestFixtures.create_plan_tables!()

    %{rows: [[prefix]]} =
      SQL.query!(Repo, "SELECT nspname FROM pg_namespace WHERE oid = pg_my_temp_schema()", [])

    assert :ok = SchemaVerifier.verify(Repo, SchemaContract.storage_tables(), prefix: prefix)

    assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} =
             SQL.query(
               Repo,
               "INSERT INTO base_agent_api_plans (id,tenant_id,binding_hash,operations_hash,preview_hash,expires_at) VALUES ('missing-tenant',999999,'a','b','c',now())",
               [], mode: :savepoint)
  end
end
