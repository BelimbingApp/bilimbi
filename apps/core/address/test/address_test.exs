defmodule Bilimbi.Core.AddressTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Address.Page

  import Bilimbi.Core.Address.TestFixtures

  setup do
    create_company_identity_tables!()
    create_geonames_tables!()
    create_address_tables!()

    insert_country!()
    insert_admin1!()
    insert_tenant!(%{id: 41, name: "Operator"})
    insert_tenant!(%{id: 42, name: "Customer", is_platform_operator: false})
    insert_company!(%{id: 73, tenant_id: 41, code: "operator"})
    insert_company!(%{id: 74, tenant_id: 42, code: "customer"})

    {:ok, operator} = Tenancy.scope(41)
    {:ok, customer} = Tenancy.scope(42)

    %{operator: operator, customer: customer}
  end

  test "creates and reads addresses only inside the explicit tenant", context do
    assert {:ok, address} =
             Address.create_address(context.operator, %{
               tenant_id: 42,
               label: "HQ",
               line1: "1 Platform Road",
               country_iso: "MY",
               normalization_notes: ["Imported from legacy source"]
             })

    assert address.tenant_id == 41
    assert address.label == "HQ"
    assert address.verification_status == "unverified"

    assert {:ok, [same_address]} = Address.list_addresses(context.operator)
    assert same_address.id == address.id
    assert {:ok, []} = Address.list_addresses(context.customer)
    assert {:error, :address_not_found} = Address.get_address(context.customer, address.id)
  end

  test "lists a bounded searchable administration page inside the explicit tenant", context do
    assert {:ok, label_match} =
             Address.create_address(context.operator, %{
               label: "Needle label",
               verification_status: "verified"
             })

    assert {:ok, line_match} =
             Address.create_address(context.operator, %{
               label: "Second",
               line1: "Needle road",
               verification_status: "suggested"
             })

    assert {:ok, locality_match} =
             Address.create_address(context.operator, %{
               label: "Third",
               locality: "Needle city"
             })

    assert {:ok, postcode_match} =
             Address.create_address(context.operator, %{
               label: "Fourth",
               postcode: "Needle postcode"
             })

    assert {:ok, country_match} =
             Address.create_address(context.operator, %{label: "Fifth", country_iso: "MY"})

    assert {:ok, other_tenant} =
             Address.create_address(context.customer, %{label: "Needle other tenant"})

    assert {:ok, deleted} =
             Address.create_address(context.operator, %{label: "Needle deleted"})

    assert :ok = Address.delete_address(context.operator, deleted.id)

    assert %Page{
             entries: first_page,
             page: 1,
             page_size: 2,
             total_entries: 4,
             total_pages: 2
           } = Address.list_addresses(context.operator, search: "Needle", page_size: 2)

    assert Enum.map(first_page, & &1.id) == [postcode_match.id, label_match.id]

    assert %Page{entries: second_page, page: 2} =
             Address.list_addresses(context.operator,
               search: "Needle",
               page: 2,
               page_size: 2
             )

    assert Enum.map(second_page, & &1.id) == [line_match.id, locality_match.id]

    assert %Page{entries: [same_country], total_entries: 1} =
             Address.list_addresses(context.operator, search: "MY")

    assert same_country.id == country_match.id
    refute other_tenant.id in Enum.map(first_page ++ second_page, & &1.id)
  end

  test "allowlists administration sorting with a newest-first creation tie-break", context do
    assert {:ok, older} =
             Address.create_address(context.operator, %{
               label: "Same",
               country_iso: "MY",
               verification_status: "verified"
             })

    assert {:ok, newer} =
             Address.create_address(context.operator, %{
               label: "Same",
               country_iso: "MY",
               verification_status: "suggested"
             })

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      "UPDATE addresses SET created_at = $1 WHERE id = $2",
      [~N[2026-08-12 12:00:00], older.id]
    )

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      "UPDATE addresses SET created_at = $1 WHERE id = $2",
      [~N[2026-08-13 12:00:00], newer.id]
    )

    assert %Page{entries: [first, second]} =
             Address.list_addresses(context.operator, sort_by: :label, sort_dir: :asc)

    assert [first.id, second.id] == [newer.id, older.id]

    assert %Page{entries: [verified, suggested]} =
             Address.list_addresses(context.operator,
               sort_by: :verification_status,
               sort_dir: :desc
             )

    assert [verified.id, suggested.id] == [older.id, newer.id]
  end

  test "rejects invalid administration page options", context do
    for options <- [
          [search: 1],
          [sort_by: :created_at],
          [sort_dir: :sideways],
          [page: 0],
          [page_size: 0],
          [page_size: 101]
        ] do
      assert_raise ArgumentError, fn -> Address.list_addresses(context.operator, options) end
    end
  end

  # A raw tenant ID or a bare tenant identity is not a scope. These are also
  # rejected statically by the type checker; the values are made opaque here so
  # the runtime clause itself is what gets asserted.
  test "cannot be called without a scope", context do
    for not_a_scope <- [41, nil, context.operator.tenant] do
      assert_raise FunctionClauseError, fn -> Address.list_addresses(opaque(not_a_scope)) end

      assert_raise FunctionClauseError, fn ->
        Address.list_addresses(opaque(not_a_scope), page: 1)
      end

      assert_raise FunctionClauseError, fn -> Address.get_address(opaque(not_a_scope), 1) end

      assert_raise FunctionClauseError, fn ->
        Address.create_address(opaque(not_a_scope), %{label: "Unscoped"})
      end
    end
  end

  test "returns changeset errors for unknown geographic references", context do
    assert {:error, country_changeset} =
             Address.create_address(context.operator, %{
               label: "Unknown country",
               country_iso: "ZZ"
             })

    assert {:country_iso, {_message, _metadata}} =
             List.keyfind(country_changeset.errors, :country_iso, 0)

    assert {:error, admin1_changeset} =
             Address.create_address(context.operator, %{
               label: "Unknown region",
               admin1_code: "MY.99"
             })

    assert {:admin1_code, {_message, _metadata}} =
             List.keyfind(admin1_changeset.errors, :admin1_code, 0)
  end

  test "updates without allowing tenant reassignment and soft deletes", context do
    assert {:ok, address} = Address.create_address(context.operator, %{label: "Old label"})

    assert {:ok, updated} =
             Address.update_address(context.operator, address.id, %{
               label: "New label",
               tenant_id: 42
             })

    assert updated.label == "New label"
    assert updated.tenant_id == 41

    assert :ok = Address.delete_address(context.operator, address.id)
    assert {:ok, []} = Address.list_addresses(context.operator)
    assert {:error, :address_not_found} = Address.get_address(context.operator, address.id)
  end

  test "attaches an address to a same-tenant company using compatible morph identity", context do
    assert {:ok, address} = Address.create_address(context.operator, %{label: "HQ"})

    assert {:ok, :attached} =
             Address.attach_to_company(context.operator, address.id, 73, %{
               kind: ["headquarters", "billing"],
               is_primary: true,
               priority: 1
             })

    assert {:ok, [attached]} = Address.list_company_addresses(context.operator, 73)
    assert attached.id == address.id

    assert [["App\\Core\\Company\\Models\\Company", ["headquarters", "billing"], true, 1]] =
             Ecto.Adapters.SQL.query!(
               Bilimbi.Base.Repo,
               "SELECT addressable_type, kind, is_primary, priority FROM addressables",
               []
             ).rows
  end

  test "updates and detaches Company pivot metadata without deleting the address", context do
    assert {:ok, address} = Address.create_address(context.operator, %{label: "Branch"})
    assert {:ok, :attached} = Address.attach_to_company(context.operator, address.id, 73)
    assert {:ok, :attached} = Address.attach_to_company(context.operator, address.id, 73)

    assert {:ok, :updated} =
             Address.update_company_attachment(context.operator, address.id, 73, %{
               kind: ["branch"],
               is_primary: true,
               priority: 3,
               valid_from: ~D[2026-08-12],
               valid_to: ~D[2026-08-13]
             })

    assert [
             [["branch"], true, 3, ~D[2026-08-12], ~D[2026-08-13]],
             [["branch"], true, 3, ~D[2026-08-12], ~D[2026-08-13]]
           ] =
             Ecto.Adapters.SQL.query!(
               Bilimbi.Base.Repo,
               """
               SELECT kind, is_primary, priority, valid_from, valid_to
               FROM addressables
               ORDER BY id
               """,
               []
             ).rows

    assert :ok = Address.detach_from_company(context.operator, address.id, 73)

    assert [[0]] =
             Ecto.Adapters.SQL.query!(
               Bilimbi.Base.Repo,
               "SELECT COUNT(*) FROM addressables",
               []
             ).rows

    assert {:ok, []} = Address.list_company_addresses(context.operator, 73)
    assert {:ok, same_address} = Address.get_address(context.operator, address.id)
    assert same_address.id == address.id
  end

  test "rejects unsupported Company attachment kinds", context do
    assert Address.company_attachment_kinds() ==
             ["headquarters", "billing", "shipping", "branch", "other"]

    assert {:ok, address} = Address.create_address(context.operator, %{label: "HQ"})

    assert {:error, changeset} =
             Address.attach_to_company(context.operator, address.id, 73, %{
               kind: ["headquarters", "warehouse"]
             })

    assert {:kind, {"contains an unsupported address kind", []}} =
             List.keyfind(changeset.errors, :kind, 0)

    assert {:ok, :attached} =
             Address.attach_to_company(context.operator, address.id, 73, %{
               kind: ["headquarters"]
             })

    assert {:error, update_changeset} =
             Address.update_company_attachment(context.operator, address.id, 73, %{
               kind: ["warehouse"]
             })

    assert {:kind, {"contains an unsupported address kind", []}} =
             List.keyfind(update_changeset.errors, :kind, 0)

    assert [[["headquarters"]]] =
             Ecto.Adapters.SQL.query!(
               Bilimbi.Base.Repo,
               "SELECT kind FROM addressables",
               []
             ).rows
  end

  test "attachment mutations fail closed outside the scoped live owner", context do
    assert {:ok, address} = Address.create_address(context.operator, %{label: "HQ"})
    assert {:ok, :attached} = Address.attach_to_company(context.operator, address.id, 73)
    insert_company!(%{id: 75, tenant_id: 41, code: "operator-secondary"})

    assert {:error, :address_not_found} =
             Address.update_company_attachment(context.customer, address.id, 74, %{priority: 2})

    assert {:error, :address_not_found} =
             Address.detach_from_company(context.customer, address.id, 74)

    assert {:error, :company_not_found} =
             Address.update_company_attachment(context.operator, address.id, 74, %{priority: 2})

    assert {:error, :attachment_not_found} =
             Address.detach_from_company(context.operator, address.id, 75)

    assert {:ok, [same_address]} = Address.list_company_addresses(context.operator, 73)
    assert same_address.id == address.id
  end

  test "refuses to soft delete an address while any owner attachment exists", context do
    assert {:ok, address} = Address.create_address(context.operator, %{label: "HQ"})
    assert {:ok, :attached} = Address.attach_to_company(context.operator, address.id, 73)

    assert {:error, :address_in_use} = Address.delete_address(context.operator, address.id)
    assert {:ok, same_address} = Address.get_address(context.operator, address.id)
    assert same_address.id == address.id

    assert :ok = Address.detach_from_company(context.operator, address.id, 73)
    assert :ok = Address.delete_address(context.operator, address.id)
  end

  test "fails closed for cross-tenant and soft-deleted owners", context do
    assert {:ok, address} = Address.create_address(context.operator, %{label: "HQ"})

    assert {:error, :company_not_found} =
             Address.attach_to_company(context.operator, address.id, 74)

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      "UPDATE companies SET deleted_at = '2026-08-12 12:00:00' WHERE id = 73",
      []
    )

    assert {:error, :company_not_found} =
             Address.attach_to_company(context.operator, address.id, 73)

    assert {:error, :company_not_found} =
             Address.list_company_addresses(context.operator, 73)
  end

  test "rejects invalid attachment date ranges", context do
    assert {:ok, address} = Address.create_address(context.operator, %{label: "Temporary"})

    assert {:error, changeset} =
             Address.attach_to_company(context.operator, address.id, 73, %{
               valid_from: ~D[2026-08-12],
               valid_to: ~D[2026-08-11]
             })

    assert {:valid_to, {_message, []}} = List.keyfind(changeset.errors, :valid_to, 0)
  end

  defp opaque(value), do: :erlang.element(1, {value})
end
