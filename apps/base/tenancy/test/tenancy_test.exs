defmodule Bilimbi.Base.TenancyTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.InvariantError
  alias Bilimbi.Base.Tenancy.NotProvisionedError
  alias Bilimbi.Base.Tenancy.SchemaContract
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Tenancy.TestFixtures.ScopedRecord

  import Bilimbi.Base.Tenancy.TestFixtures

  setup do
    create_tenants_table!()
    :ok
  end

  test "resolves the explicitly marked live platform operator" do
    insert_tenant!(%{id: 41})

    tenant = Tenancy.platform_operator()

    assert tenant.id == 41
    assert Tenancy.platform_operator?(tenant)
    assert Tenancy.require_platform_operator!().id == 41
  end

  test "lists and counts live tenants without leaking the Ecto schema" do
    insert_tenant!(%{id: 41, name: "Zulu operator"})
    insert_tenant!(%{id: 42, name: "Alpha customer", is_platform_operator: false})
    insert_tenant!(%{
      id: 43,
      name: "Gone",
      is_platform_operator: false,
      deleted_at: ~N[2026-08-12 12:00:00]
    })

    tenants = Tenancy.list_tenants()

    assert Enum.map(tenants, & &1.name) == ["Alpha customer", "Zulu operator"]
    assert Enum.map(tenants, & &1.id) == [42, 41]
    refute Enum.any?(tenants, &Map.has_key?(&1, :__meta__))
    assert Tenancy.count_tenants() == 2
  end

  test "exposes tenant identity without leaking the Ecto schema and owns locked reads" do
    insert_tenant!(%{id: 41, is_platform_operator: false})

    assert {:ok, tenant} = Tenancy.lock_tenant(41)
    assert tenant.id == 41
    refute Map.has_key?(tenant, :__meta__)
    assert {:error, :not_found} = Tenancy.fetch_tenant(999)
  end

  test "reports an unprovisioned operator without assigning meaning to an ID" do
    insert_tenant!(%{id: 1, is_platform_operator: false})

    assert Tenancy.platform_operator() == nil
    assert_raise NotProvisionedError, &Tenancy.require_platform_operator!/0
  end

  test "rejects a soft-deleted marked operator" do
    insert_tenant!(%{deleted_at: ~N[2026-08-11 12:00:00]})

    assert {:error, [error]} =
             SchemaContract.verify_invariants(Repo, prefix: temporary_schema!())

    assert error =~ "platform-operator tenant 41 is soft-deleted"
    assert_raise InvariantError, &Tenancy.platform_operator/0
  end

  test "provisions one generated operator and updates it idempotently" do
    assert {:ok, first, :created} = Tenancy.provision_platform_operator("Initial operator")
    assert first.is_platform_operator

    assert {:ok, second, :existing} = Tenancy.provision_platform_operator("Renamed operator")
    assert second.id == first.id
    assert second.name == "Renamed operator"
    assert Tenancy.platform_operator().id == first.id
  end

  test "normal tenant creation cannot smuggle operator identity or an ID" do
    assert {:ok, tenant} =
             Tenancy.create_tenant(%{
               id: 999,
               name: "Customer tenant",
               is_platform_operator: true
             })

    assert tenant.id != 999
    refute tenant.is_platform_operator
  end

  describe "scope/1" do
    test "carries the live tenant it was proven from" do
      insert_tenant!(%{id: 41, name: "Operator"})

      assert {:ok, %Scope{} = scope} = Tenancy.scope(41)
      assert Scope.tenant_id(scope) == 41
      assert Scope.tenant(scope).name == "Operator"
      assert Scope.platform_operator?(scope)
    end

    test "cannot be built for a missing or soft-deleted tenant" do
      insert_tenant!(%{id: 41, is_platform_operator: false})

      assert {:error, :not_found} = Tenancy.scope(999)

      Ecto.Adapters.SQL.query!(
        Repo,
        "UPDATE tenants SET deleted_at = '2026-08-12 12:00:00' WHERE id = 41",
        []
      )

      assert {:error, :soft_deleted} = Tenancy.scope(41)
    end
  end

  describe "scope_query/2" do
    setup do
      create_scoped_records_table!()
      insert_tenant!(%{id: 41})
      insert_tenant!(%{id: 42, is_platform_operator: false})
      insert_scoped_record!(41, "owned")
      insert_scoped_record!(42, "foreign")

      {:ok, scope} = Tenancy.scope(41)
      %{scope: scope}
    end

    test "constrains the query to the scope's tenant", %{scope: scope} do
      assert [%{label: "owned"}] = Repo.all(Tenancy.scope_query(ScopedRecord, scope))
    end

    # These calls are also rejected statically by the type checker; the values
    # are made opaque here so the runtime clause itself is what gets asserted.
    test "raises rather than returning an unfiltered query", %{scope: scope} do
      for not_a_scope <- [nil, 41, %{tenant_id: 41}, Scope.tenant(scope)] do
        assert_raise FunctionClauseError, fn ->
          Tenancy.scope_query(ScopedRecord, opaque(not_a_scope))
        end
      end
    end

    test "names its binding so correlated subqueries can reference it", %{scope: scope} do
      query =
        from record in Tenancy.scope_query(ScopedRecord, scope),
          where:
            exists(
              from other in ScopedRecord,
                where: other.id == parent_as(:scoped).id
            )

      assert [%{label: "owned"}] = Repo.all(query)
    end
  end

  defp opaque(value), do: :erlang.element(1, {value})
end
