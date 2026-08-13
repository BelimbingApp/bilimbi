defmodule Bilimbi.Core.AddressTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Address
  alias Bilimbi.Core.Address.Detail
  alias Bilimbi.Core.Address.Page
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee

  import Bilimbi.Core.Address.TestFixtures

  setup do
    create_owner_identity_tables!()
    create_geonames_tables!()
    create_address_tables!()

    insert_country!()
    insert_admin1!()
    insert_tenant!(%{id: 41, name: "Operator"})
    insert_tenant!(%{id: 42, name: "Customer", is_platform_operator: false})
    insert_company!(%{id: 73, tenant_id: 41, name: "Alpha Company", code: "operator"})
    insert_company!(%{id: 74, tenant_id: 42, name: "Other Company", code: "customer"})
    :ok = Employee.ensure_system_types()

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

  test "returns source and normalized-location detail without exposing schemas", context do
    assert {:ok, address} =
             Address.create_address(context.operator, %{
               label: "HQ",
               phone: "+60 3 1234 5678",
               line1: "1 Platform Road",
               line2: "Level 2",
               locality: "Kuala Lumpur",
               postcode: "50000",
               country_iso: "MY",
               admin1_code: "MY.14",
               raw_input: "1 Platform Road, Kuala Lumpur",
               source: "import",
               source_ref: "legacy-42",
               parser_version: "2.1",
               parse_confidence: Decimal.new("0.9876"),
               parsed_at: ~N[2026-08-12 09:30:00],
               normalized_at: ~N[2026-08-12 09:31:00],
               normalization_notes: ["postcode matched"],
               verification_status: "verified",
               metadata: %{"batch" => 7}
             })

    assert {:ok, %Detail{} = detail} =
             Address.get_address_detail(context.operator, address.id)

    assert detail.id == address.id
    assert detail.tenant_id == 41
    assert detail.country_name == "Malaysia"
    assert detail.admin1_name == "Kuala Lumpur"
    assert detail.source == "import"
    assert detail.source_ref == "legacy-42"
    assert detail.parser_version == "2.1"
    assert detail.parse_confidence == Decimal.new("0.9876")
    assert detail.raw_input == "1 Platform Road, Kuala Lumpur"
    assert detail.normalization_notes == ["postcode matched"]
    assert detail.metadata == %{"batch" => 7}
    assert detail.linked_owners == []

    assert {:error, :address_not_found} =
             Address.get_address_detail(context.customer, address.id)
  end

  test "projects and sorts only live same-tenant Company and Employee owners", context do
    insert_company!(%{
      id: 75,
      tenant_id: 41,
      name: "Zulu Company",
      code: "operator-secondary"
    })

    insert_company!(%{
      id: 76,
      tenant_id: 41,
      name: "Deleted Company",
      code: "operator-deleted"
    })

    assert {:ok, employee} =
             Employee.create_employee(context.operator, 73, %{
               employee_number: "EMP-OWNER",
               full_name: "Bravo Employee"
             })

    assert {:ok, cross_tenant_employee} =
             Employee.create_employee(context.customer, 74, %{
               employee_number: "EMP-OTHER",
               full_name: "Other Employee"
             })

    assert {:ok, deleted_company_employee} =
             Employee.create_employee(context.operator, 76, %{
               employee_number: "EMP-DELETED",
               full_name: "Deleted Company Employee"
             })

    assert {:ok, address} = Address.create_address(context.operator, %{label: "Shared"})

    assert {:ok, :attached} =
             Address.attach_to_company(context.operator, address.id, 73, %{
               kind: ["shipping"],
               priority: 5,
               valid_from: ~D[2026-01-02],
               valid_to: ~D[2026-01-05]
             })

    assert {:ok, :attached} =
             Address.attach_to_company(context.operator, address.id, 75, %{
               kind: ["billing"],
               is_primary: true,
               priority: 1,
               valid_from: ~D[2026-01-03]
             })

    insert_attachment!(%{
      address_id: address.id,
      addressable_type: Employee.addressable_identity(),
      addressable_id: employee.id,
      kind: ["branch"],
      priority: 3,
      valid_from: ~D[2026-01-01],
      valid_to: ~D[2026-01-04]
    })

    for {type, owner_id} <- [
          {Company.addressable_identity(), 74},
          {Employee.addressable_identity(), cross_tenant_employee.id},
          {Company.addressable_identity(), 76},
          {Employee.addressable_identity(), deleted_company_employee.id},
          {Company.addressable_identity(), 999_999},
          {"App\\Domain\\Unknown\\Models\\Owner", 1}
        ] do
      insert_attachment!(%{
        address_id: address.id,
        addressable_type: type,
        addressable_id: owner_id
      })
    end

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      "UPDATE companies SET deleted_at = '2026-08-12 12:00:00' WHERE id = 76",
      []
    )

    assert_owner_order(context.operator, address.id, :type, :asc, [
      {:company, 73},
      {:company, 75},
      {:employee, employee.id}
    ])

    assert_owner_order(context.operator, address.id, :name, :asc, [
      {:company, 73},
      {:employee, employee.id},
      {:company, 75}
    ])

    assert_owner_order(context.operator, address.id, :kind, :asc, [
      {:company, 75},
      {:employee, employee.id},
      {:company, 73}
    ])

    assert_owner_order(context.operator, address.id, :is_primary, :desc, [
      {:company, 75},
      {:employee, employee.id},
      {:company, 73}
    ])

    assert_owner_order(context.operator, address.id, :priority, :asc, [
      {:company, 75},
      {:employee, employee.id},
      {:company, 73}
    ])

    assert_owner_order(context.operator, address.id, :valid_from, :asc, [
      {:employee, employee.id},
      {:company, 73},
      {:company, 75}
    ])

    assert_owner_order(context.operator, address.id, :valid_to, :asc, [
      {:company, 75},
      {:employee, employee.id},
      {:company, 73}
    ])

    assert {:ok, detail} = Address.get_address_detail(context.operator, address.id)

    assert Enum.map(detail.linked_owners, & &1.name) == [
             "Alpha Company",
             "Zulu Company",
             "Bravo Employee"
           ]

    assert_raise ArgumentError, fn ->
      Address.get_address_detail(context.operator, address.id, owner_sort_by: :created_at)
    end

    assert_raise ArgumentError, fn ->
      Address.get_address_detail(context.operator, address.id, owner_sort_dir: :sideways)
    end
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
        Address.get_address_detail(opaque(not_a_scope), 1)
      end

      assert_raise FunctionClauseError, fn ->
        Address.create_address(opaque(not_a_scope), %{label: "Unscoped"})
      end

      assert_raise FunctionClauseError, fn ->
        Address.list_available_company_addresses(opaque(not_a_scope), 73)
      end

      assert_raise FunctionClauseError, fn ->
        Address.create_and_attach_to_company(opaque(not_a_scope), 73, %{label: "Unscoped"})
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

  test "lists live same-tenant addresses not already linked to the Company", context do
    insert_company!(%{id: 75, tenant_id: 41, code: "operator-secondary"})

    assert {:ok, linked} = Address.create_address(context.operator, %{label: "Linked"})
    assert {:ok, alpha} = Address.create_address(context.operator, %{label: "Alpha"})
    assert {:ok, zulu} = Address.create_address(context.operator, %{label: "Zulu"})
    assert {:ok, deleted} = Address.create_address(context.operator, %{label: "Deleted"})
    assert {:ok, _other_tenant} = Address.create_address(context.customer, %{label: "Aardvark"})

    assert {:ok, :attached} = Address.attach_to_company(context.operator, linked.id, 73)
    assert {:ok, :attached} = Address.attach_to_company(context.operator, zulu.id, 75)
    assert :ok = Address.delete_address(context.operator, deleted.id)

    assert {:ok, available} =
             Address.list_available_company_addresses(context.operator, 73)

    assert Enum.map(available, & &1.id) == [alpha.id, zulu.id]

    assert {:error, :company_not_found} =
             Address.list_available_company_addresses(context.operator, 74)
  end

  test "creates a manual address and Company attachment atomically", context do
    assert {:ok, address} =
             Address.create_and_attach_to_company(
               context.operator,
               73,
               %{
                 tenant_id: 42,
                 label: "New branch",
                 source: "imported",
                 verification_status: "verified"
               },
               %{kind: ["branch"], is_primary: true, priority: 2}
             )

    assert address.tenant_id == 41
    assert address.verification_status == "unverified"

    assert [[41, "manual", "unverified", ["branch"], true, 2, valid_from]] =
             Ecto.Adapters.SQL.query!(
               Bilimbi.Base.Repo,
               """
               SELECT addresses.tenant_id, addresses.source, addresses."verificationStatus",
                      addressables.kind, addressables.is_primary, addressables.priority,
                      addressables.valid_from
               FROM addresses
               JOIN addressables ON addressables.address_id = addresses.id
               """,
               []
             ).rows

    assert valid_from == Date.utc_today()
  end

  test "rolls back create-and-attach when either changeset or the Company is invalid", context do
    assert {:error, address_changeset} =
             Address.create_and_attach_to_company(context.operator, 73, %{
               label: "Unknown country",
               country_iso: "ZZ"
             })

    assert {:country_iso, {_message, _metadata}} =
             List.keyfind(address_changeset.errors, :country_iso, 0)

    assert {:error, attachment_changeset} =
             Address.create_and_attach_to_company(
               context.operator,
               73,
               %{label: "Invalid attachment"},
               %{kind: ["warehouse"]}
             )

    assert {:kind, {"contains an unsupported address kind", []}} =
             List.keyfind(attachment_changeset.errors, :kind, 0)

    assert {:error, date_changeset} =
             Address.create_and_attach_to_company(
               context.operator,
               73,
               %{"label" => "Invalid dates"},
               %{"valid_to" => Date.add(Date.utc_today(), -1)}
             )

    assert {:valid_to, {"must be on or after valid_from", []}} =
             List.keyfind(date_changeset.errors, :valid_to, 0)

    assert {:error, :company_not_found} =
             Address.create_and_attach_to_company(context.operator, 74, %{
               label: "Cross-tenant owner"
             })

    Ecto.Adapters.SQL.query!(
      Bilimbi.Base.Repo,
      "UPDATE companies SET deleted_at = '2026-08-12 12:00:00' WHERE id = 73",
      []
    )

    assert {:error, :company_not_found} =
             Address.create_and_attach_to_company(context.operator, 73, %{
               label: "Deleted owner"
             })

    assert [[0, 0]] =
             Ecto.Adapters.SQL.query!(
               Bilimbi.Base.Repo,
               "SELECT (SELECT COUNT(*) FROM addresses), (SELECT COUNT(*) FROM addressables)",
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

  defp assert_owner_order(scope, address_id, sort_by, sort_dir, expected) do
    assert {:ok, detail} =
             Address.get_address_detail(scope, address_id,
               owner_sort_by: sort_by,
               owner_sort_dir: sort_dir
             )

    assert Enum.map(detail.linked_owners, &{&1.owner_type, &1.owner_id}) == expected
  end

  defp opaque(value), do: :erlang.element(1, {value})
end
