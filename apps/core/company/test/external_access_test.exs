defmodule Bilimbi.Core.Company.ExternalAccessTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.ExternalAccessSummary

  import Bilimbi.Core.Company.TestFixtures

  setup do
    create_company_identity_tables!()
    create_external_access_tables!()
    insert_tenant!(%{id: 41})
    insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})
    insert_company!(%{id: 73, tenant_id: 41})
    insert_company!(%{id: 75, tenant_id: 41, code: "related", name: "Related"})
    insert_company!(%{id: 74, tenant_id: 42, code: "elsewhere", name: "Elsewhere"})
    insert_relationship_type!(11)
    insert_relationship!(21, 73, 75)
    insert_relationship!(22, 74, 74)

    {:ok, owner} = Tenancy.scope(41)
    {:ok, other} = Tenancy.scope(42)
    %{owner: owner, other: other}
  end

  test "creates, lists, and resolves accesses inside the granting company", %{owner: owner} do
    assert {:ok, access} =
             Company.create_external_access(owner, 73, %{
               relationship_id: 21,
               user_id: 91,
               permissions: ["view_orders"],
               access_granted_at: ~N[2026-01-01 00:00:00]
             })

    assert access.company_id == 73
    assert access.relationship_id == 21
    assert access.user_id == 91
    assert access.is_active
    assert ExternalAccessSummary.valid?(access, ~N[2026-06-01 00:00:00])

    assert {:ok, [listed]} = Company.list_external_accesses(owner, 73)
    assert listed.id == access.id
    assert {:ok, [^listed]} = Company.list_external_accesses(owner, 73, 91)
    assert {:ok, []} = Company.list_external_accesses(owner, 73, 99)
    assert {:ok, fetched} = Company.get_external_access(owner, 73, access.id)
    assert fetched.permissions == ["view_orders"]
  end

  test "refuses a relationship that does not belong to the granting company", %{
    owner: owner
  } do
    assert {:error, :relationship_not_found} =
             Company.create_external_access(owner, 73, %{relationship_id: 22})
  end

  test "isolates tenants and refuses a soft-deleted granting company", %{
    owner: owner,
    other: other
  } do
    assert {:ok, access} =
             Company.create_external_access(owner, 73, %{relationship_id: 21, user_id: 91})

    assert {:error, :company_not_found} = Company.list_external_accesses(other, 73)
    assert {:error, :company_not_found} = Company.get_external_access(other, 73, access.id)

    insert_company!(%{
      id: 76,
      tenant_id: 41,
      code: "archived",
      deleted_at: ~N[2026-08-11 12:00:00]
    })

    assert {:error, :company_not_found} = Company.list_external_accesses(owner, 76)
  end

  test "grant, revoke, and validity follow Belimbing ExternalAccess semantics", %{owner: owner} do
    assert {:ok, pending} =
             Company.create_external_access(owner, 73, %{
               relationship_id: 21,
               is_active: true,
               access_granted_at: ~N[2027-01-01 00:00:00]
             })

    refute ExternalAccessSummary.valid?(pending, ~N[2026-06-01 00:00:00])

    assert {:ok, granted} = Company.grant_external_access(owner, 73, pending.id)
    assert granted.is_active
    assert granted.access_granted_at
    assert ExternalAccessSummary.valid?(granted, NaiveDateTime.utc_now())

    assert {:ok, revoked} = Company.revoke_external_access(owner, 73, granted.id)
    refute revoked.is_active
    refute ExternalAccessSummary.valid?(revoked)

    assert {:ok, expired} =
             Company.create_external_access(owner, 73, %{
               relationship_id: 21,
               access_granted_at: ~N[2026-01-01 00:00:00],
               access_expires_at: ~N[2026-02-01 00:00:00]
             })

    refute ExternalAccessSummary.valid?(expired, ~N[2026-06-01 00:00:00])
  end

  test "soft-deletes an access and treats a second delete as missing", %{owner: owner} do
    assert {:ok, access} =
             Company.create_external_access(owner, 73, %{relationship_id: 21})

    assert :ok = Company.delete_external_access(owner, 73, access.id)
    assert {:error, :not_found} = Company.get_external_access(owner, 73, access.id)
    assert {:ok, []} = Company.list_external_accesses(owner, 73)
    assert {:error, :not_found} = Company.delete_external_access(owner, 73, access.id)
    assert {:error, :not_found} = Company.update_external_access(owner, 73, access.id, %{})
  end

  test "nullifies user_id when the optional owner row is deleted", %{owner: owner} do
    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      """
      CREATE TEMPORARY TABLE users (
        id bigserial PRIMARY KEY
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      """
      ALTER TABLE company_external_accesses
      ADD CONSTRAINT company_external_accesses_user_id_foreign
      FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
      """,
      []
    )

    Ecto.Adapters.SQL.query!(Bilimbi.Base.Repo, "INSERT INTO users (id) VALUES (91)", [])

    assert {:ok, access} =
             Company.create_external_access(owner, 73, %{relationship_id: 21, user_id: 91})

    assert access.user_id == 91
    Ecto.Adapters.SQL.query!(Bilimbi.Base.Repo, "DELETE FROM users WHERE id = 91", [])
    assert {:ok, cleared} = Company.get_external_access(owner, 73, access.id)
    assert cleared.user_id == nil
  end

  test "cannot be called without a scope", %{owner: owner} do
    for not_a_scope <- [41, nil, owner.tenant] do
      assert_raise FunctionClauseError, fn ->
        Company.list_external_accesses(opaque(not_a_scope), 73)
      end
    end
  end

  defp opaque(value), do: :erlang.element(1, {value})
end
