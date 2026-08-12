defmodule Bilimbi.Core.AddressTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Core.Address

  import Bilimbi.Core.Address.TestFixtures

  setup do
    create_company_identity_tables!()
    create_address_tables!()

    insert_tenant!(%{id: 41, name: "Operator"})
    insert_tenant!(%{id: 42, name: "Customer", is_platform_operator: false})
    insert_company!(%{id: 73, tenant_id: 41, code: "operator"})
    insert_company!(%{id: 74, tenant_id: 42, code: "customer"})

    :ok
  end

  test "creates and reads addresses only inside the explicit tenant" do
    assert {:ok, address} =
             Address.create_address(41, %{
               tenant_id: 42,
               label: "HQ",
               line1: "1 Platform Road",
               country_iso: "MY",
               normalization_notes: ["Imported from legacy source"]
             })

    assert address.tenant_id == 41
    assert address.label == "HQ"
    assert address.verification_status == "unverified"

    assert {:ok, [same_address]} = Address.list_addresses(41)
    assert same_address.id == address.id
    assert {:ok, []} = Address.list_addresses(42)
    assert {:error, :address_not_found} = Address.get_address(42, address.id)
  end

  test "rejects missing and soft-deleted tenants" do
    assert {:error, :tenant_not_found} = Address.create_address(999, %{label: "Nowhere"})

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      "UPDATE tenants SET deleted_at = '2026-08-12 12:00:00' WHERE id = 42",
      []
    )

    assert {:error, :tenant_not_found} = Address.create_address(42, %{label: "Closed"})
  end

  test "updates without allowing tenant reassignment and soft deletes" do
    assert {:ok, address} = Address.create_address(41, %{label: "Old label"})

    assert {:ok, updated} =
             Address.update_address(41, address.id, %{label: "New label", tenant_id: 42})

    assert updated.label == "New label"
    assert updated.tenant_id == 41

    assert :ok = Address.delete_address(41, address.id)
    assert {:ok, []} = Address.list_addresses(41)
    assert {:error, :address_not_found} = Address.get_address(41, address.id)
  end

  test "attaches an address to a same-tenant company using compatible morph identity" do
    assert {:ok, address} = Address.create_address(41, %{label: "HQ"})

    assert {:ok, :attached} =
             Address.attach_to_company(41, address.id, 73, %{
               is_primary: true,
               priority: 1
             })

    assert {:ok, [attached]} = Address.list_company_addresses(41, 73)
    assert attached.id == address.id

    assert [["App\\Core\\Company\\Models\\Company"]] =
             Ecto.Adapters.SQL.query!(
               Bilimbi.Base.Repo,
               "SELECT addressable_type FROM addressables",
               []
             ).rows
  end

  test "fails closed for cross-tenant and soft-deleted owners" do
    assert {:ok, address} = Address.create_address(41, %{label: "HQ"})

    assert {:error, :company_not_found} = Address.attach_to_company(41, address.id, 74)

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      "UPDATE companies SET deleted_at = '2026-08-12 12:00:00' WHERE id = 73",
      []
    )

    assert {:error, :company_not_found} = Address.attach_to_company(41, address.id, 73)
    assert {:error, :company_not_found} = Address.list_company_addresses(41, 73)
  end

  test "rejects invalid attachment date ranges" do
    assert {:ok, address} = Address.create_address(41, %{label: "Temporary"})

    assert {:error, changeset} =
             Address.attach_to_company(41, address.id, 73, %{
               valid_from: ~D[2026-08-12],
               valid_to: ~D[2026-08-11]
             })

    assert {:valid_to, {_message, []}} = List.keyfind(changeset.errors, :valid_to, 0)
  end
end
