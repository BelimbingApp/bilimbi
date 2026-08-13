defmodule Bilimbi.Core.Company.ExternalAccessLockTest do
  @moduledoc false

  # async: false — two real connections must observe each other's uncommitted
  # row locks. Temp-table DataCase tests cannot do that.
  use ExUnit.Case, async: false

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  test "a waiting delete returns not_found after the lock holder commits a soft-delete" do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    schema = "company_ext_access_lock_#{System.unique_integer([:positive])}"
    create_lock_schema!(schema)
    on_exit(fn -> drop_lock_schema!(schema) end)

    {scope, access_id} =
      on_schema!(schema, fn ->
        {:ok, scope} = Tenancy.scope(41)

        {:ok, access} =
          Company.create_external_access(scope, 73, %{relationship_id: 21})

        {scope, access.id}
      end)

    parent = self()

    holder =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        on_schema!(schema, fn ->
          Repo.transaction(fn ->
            %{rows: [[^access_id]]} =
              SQL.query!(
                Repo,
                "SELECT id FROM company_external_accesses WHERE id = $1 FOR UPDATE",
                [access_id]
              )

            send(parent, :holder_locked)

            receive do
              :commit_delete -> :ok
            after
              5_000 -> Repo.rollback(:holder_timeout)
            end

            Company.delete_external_access(scope, 73, access_id)
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
          Company.delete_external_access(scope, 73, access_id)
        end)
      end)

    assert_receive {:contender_backend, backend_pid}, 5_000
    await_backend_lock_wait!(backend_pid)
    send(holder.pid, :commit_delete)

    assert {:ok, :ok} = Task.await(holder, 5_000)
    assert {:error, :not_found} = Task.await(contender, 5_000)

    on_schema!(schema, fn ->
      assert {:error, :not_found} = Company.get_external_access(scope, 73, access_id)
    end)
  end

  # update/revoke/delete share mutate_live_access/4 (FOR UPDATE, then mutate).
  # One delete-vs-delete wait/recheck proves the helper: the waiter re-evaluates
  # `deleted_at IS NULL` after the holder commits.

  defp await_backend_lock_wait!(backend_pid) do
    await_backend_lock_wait!(backend_pid, 50)
  end

  defp await_backend_lock_wait!(_backend_pid, 0) do
    flunk("contender never waited on a PostgreSQL row lock")
  end

  defp await_backend_lock_wait!(backend_pid, remaining) do
    %{rows: rows} =
      SQL.query!(
        Repo,
        "SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1",
        [backend_pid]
      )

    case rows do
      [["Lock"]] ->
        :ok

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
    s = quote_ident(schema)

    SQL.query!(Repo, "CREATE SCHEMA #{s}", [])

    SQL.query!(
      Repo,
      """
      CREATE TABLE #{s}.tenants (
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
      CREATE TABLE #{s}.companies (
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
      CREATE TABLE #{s}.company_relationships (
        id bigserial PRIMARY KEY,
        company_id bigint NOT NULL,
        related_company_id bigint NOT NULL,
        relationship_type_id bigint NOT NULL,
        deleted_at timestamp(0) without time zone
      )
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TABLE #{s}.company_external_accesses (
        id bigserial PRIMARY KEY,
        company_id bigint NOT NULL,
        relationship_id bigint NOT NULL,
        user_id bigint,
        permissions json,
        is_active boolean NOT NULL DEFAULT true,
        access_granted_at timestamp(0) without time zone,
        access_expires_at timestamp(0) without time zone,
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
      INSERT INTO #{s}.tenants (id, name, status, is_platform_operator)
      VALUES (41, 'Platform operator', 'active', true)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO #{s}.companies (id, tenant_id, name, code, status)
      VALUES (73, 41, 'Bilimbi Industries', 'bilimbi_industries', 'active')
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO #{s}.company_relationships
        (id, company_id, related_company_id, relationship_type_id)
      VALUES (21, 73, 73, 11)
      """,
      []
    )
  end

  defp drop_lock_schema!(schema) do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    SQL.query!(Repo, "DROP SCHEMA IF EXISTS #{quote_ident(schema)} CASCADE", [])
  end

  defp quote_ident(name) when is_binary(name) do
    if name =~ ~r/^[a-z0-9_]+$/ do
      name
    else
      raise "refusing to interpolate #{inspect(name)} as an identifier"
    end
  end
end
