defmodule Bilimbi.Core.Company.LiveLockTest do
  @moduledoc false

  # async: false — this contract requires two independently checked-out
  # PostgreSQL connections that can observe each other's row locks.
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.LiveCompanyProof
  alias Bilimbi.Core.Company.Schema
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    schema = "company_live_lock_#{System.unique_integer([:positive])}"
    create_lock_schema!(schema)
    on_exit(fn -> drop_lock_schema!(schema) end)

    scope = on_schema!(schema, fn -> {:ok, scope} = Tenancy.scope(41); scope end)
    %{schema: schema, scope: scope}
  end

  test "requires an explicit shared Repo transaction", %{schema: schema, scope: scope} do
    on_schema!(schema, fn ->
      refute Repo.in_transaction?()
      assert {:error, :transaction_required} = Company.lock_live_company(scope, 73)

      assert {:ok, %LiveCompanyProof{id: 73}} =
               Repo.transaction(fn ->
                 assert Repo.in_transaction?()
                 Company.lock_live_company(scope, 73)
               end)
    end)
  end

  test "returns generic misses and keeps its proof schema-free", %{schema: schema, scope: scope} do
    on_schema!(schema, fn ->
      assert {:ok, %LiveCompanyProof{id: 73} = proof} =
               Repo.transaction(fn -> Company.lock_live_company(scope, 73) end)

      assert Map.keys(Map.from_struct(proof)) == [:id]
      refute is_struct(proof, Schema)
      refute Map.has_key?(proof, :__meta__)

      assert_raise Protocol.UndefinedError, fn ->
        Ecto.Queryable.to_query(proof)
      end

      for company_id <- [0, -1, nil, "73", 74, 75] do
        assert {:ok, {:error, :not_found}} =
                 Repo.transaction(fn -> Company.lock_live_company(scope, company_id) end)
      end
    end)
  end

  test "rejects a malformed scope at the public boundary", %{schema: schema} do
    on_schema!(schema, fn ->
      assert_raise FunctionClauseError, fn ->
        Repo.transaction(fn -> Company.lock_live_company(41, 73) end)
      end
    end)
  end

  test "rollback releases a proof lock without returning a durable capability", %{
    schema: schema,
    scope: scope
  } do
    on_schema!(schema, fn ->
      assert {:error, :rollback} =
               Repo.transaction(fn ->
                 assert {:ok, %LiveCompanyProof{id: 73}} = Company.lock_live_company(scope, 73)
                 Repo.rollback(:rollback)
               end)

      assert {:ok, %LiveCompanyProof{id: 73}} =
               Repo.transaction(fn -> Company.lock_live_company(scope, 73) end)
    end)
  end

  test "the proof retains its row lock until commit", %{schema: schema, scope: scope} do
    parent = self()

    holder =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        on_schema!(schema, fn ->
          Repo.transaction(fn ->
            assert {:ok, %LiveCompanyProof{id: 73}} = Company.lock_live_company(scope, 73)
            send(parent, :holder_locked)
            await_message!(:commit_holder)
          end)
        end)
      end)

    assert_receive :holder_locked, 5_000

    contender =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        on_schema!(schema, fn ->
          %{rows: [[backend_pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
          send(parent, {:contender_backend, backend_pid})

          SQL.query!(
            Repo,
            "UPDATE companies SET deleted_at = '2026-08-14 00:00:00' WHERE id = $1",
            [73]
          )
        end)
      end)

    assert_receive {:contender_backend, backend_pid}, 5_000
    await_backend_lock_wait!(backend_pid)
    send(holder.pid, :commit_holder)

    assert {:ok, :ok} = Task.await(holder, 5_000)
    assert %{num_rows: 1} = Task.await(contender, 5_000)

    on_schema!(schema, fn ->
      assert {:ok, {:error, :not_found}} =
               Repo.transaction(fn -> Company.lock_live_company(scope, 73) end)
    end)
  end

  test "a waiting proof rechecks after a competing soft-delete commits", %{
    schema: schema,
    scope: scope
  } do
    parent = self()

    holder =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        on_schema!(schema, fn ->
          Repo.transaction(fn ->
            %{rows: [[73]]} = SQL.query!(Repo, "SELECT id FROM companies WHERE id = 73 FOR UPDATE", [])
            send(parent, :delete_holder_locked)
            await_message!(:soft_delete_and_commit)

            SQL.query!(
              Repo,
              "UPDATE companies SET deleted_at = '2026-08-14 00:00:00' WHERE id = $1",
              [73]
            )
          end)
        end)
      end)

    assert_receive :delete_holder_locked, 5_000

    contender =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        on_schema!(schema, fn ->
          %{rows: [[backend_pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
          send(parent, {:proof_contender_backend, backend_pid})

          Repo.transaction(fn -> Company.lock_live_company(scope, 73) end)
        end)
      end)

    assert_receive {:proof_contender_backend, backend_pid}, 5_000
    await_backend_lock_wait!(backend_pid)
    send(holder.pid, :soft_delete_and_commit)

    assert {:ok, %{num_rows: 1}} = Task.await(holder, 5_000)
    assert {:ok, {:error, :not_found}} = Task.await(contender, 5_000)
  end

  defp await_message!(message) do
    receive do
      ^message -> :ok
    after
      5_000 -> Repo.rollback({:timeout, message})
    end
  end

  defp await_backend_lock_wait!(backend_pid), do: await_backend_lock_wait!(backend_pid, 50)

  defp await_backend_lock_wait!(_backend_pid, 0), do: flunk("contender never waited on a row lock")

  defp await_backend_lock_wait!(backend_pid, remaining) do
    %{rows: rows} =
      SQL.query!(Repo, "SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [backend_pid])

    case rows do
      [["Lock"]] -> :ok

      _other ->
        receive do
        after
          20 -> await_backend_lock_wait!(backend_pid, remaining - 1)
        end
    end
  end

  defp on_schema!(schema, fun) do
    SQL.query!(Repo, "SET search_path TO #{quote_ident(schema)}", [])

    try do
      fun.()
    after
      SQL.query!(Repo, "SET search_path TO public", [])
    end
  end

  defp create_lock_schema!(schema) do
    quoted_schema = quote_ident(schema)
    SQL.query!(Repo, "CREATE SCHEMA #{quoted_schema}", [])

    SQL.query!(
      Repo,
      """
      CREATE TABLE #{quoted_schema}.tenants (
        id bigserial PRIMARY KEY,
        parent_id bigint,
        name varchar(255) NOT NULL,
        status varchar(255) NOT NULL DEFAULT 'active',
        is_platform_operator boolean NOT NULL DEFAULT false,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        deleted_at timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TABLE #{quoted_schema}.companies (
        id bigserial PRIMARY KEY,
        parent_id bigint,
        tenant_id bigint NOT NULL,
        name varchar(255) NOT NULL,
        code varchar(255) NOT NULL UNIQUE,
        status varchar(255) NOT NULL DEFAULT 'active',
        legal_name varchar(255),
        registration_number varchar(255),
        tax_id varchar(255),
        legal_entity_type_id bigint,
        jurisdiction varchar(255),
        email varchar(255),
        website varchar(255),
        scope_activities json,
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        deleted_at timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO #{quoted_schema}.tenants (id, name, status, is_platform_operator)
      VALUES (41, 'Owner', 'active', true), (42, 'Other', 'active', false)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO #{quoted_schema}.companies (id, tenant_id, name, code, status, deleted_at)
      VALUES
        (73, 41, 'Live', 'live', 'active', NULL),
        (74, 42, 'Foreign', 'foreign', 'active', NULL),
        (75, 41, 'Deleted', 'deleted', 'active', '2026-08-13 00:00:00')
      """,
      []
    )
  end

  defp drop_lock_schema!(schema) do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    SQL.query!(Repo, "DROP SCHEMA IF EXISTS #{quote_ident(schema)} CASCADE", [])
  end

  defp quote_ident(name) when is_binary(name) and name =~ ~r/^[a-z0-9_]+$/, do: name
end
