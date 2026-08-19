defmodule Bilimbi.Core.CompanyTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.AuthzCompanyDirectory
  alias Bilimbi.Core.Company.PrimaryCompanyManager
  alias Bilimbi.Core.Company.SchemaContract
  alias Bilimbi.Core.Company.Summary

  import Bilimbi.Core.Company.TestFixtures

  setup do
    create_company_identity_tables!()
    :ok
  end

  test "returns the explicit platform-operator primary company through a stable read model" do
    insert_tenant!()
    insert_company!(%{legal_name: "Bilimbi Industries Sdn. Bhd."})
    assign_primary_company!()

    assert {:ok,
            %Summary{
              id: 73,
              tenant_id: 41,
              name: "Bilimbi Industries",
              code: "bilimbi_industries",
              status: "active",
              legal_name: "Bilimbi Industries Sdn. Bhd."
            }} = Company.platform_operator_company()

    assert PrimaryCompanyManager.primary?(PrimaryCompanyManager.platform_operator_company!())
  end

  test "publishes the durable addressable identity it owns" do
    assert Company.addressable_identity() == "App\\Core\\Company\\Models\\Company"
  end

  test "validates department ownership through the Company boundary" do
    insert_tenant!()
    insert_company!()
    insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})
    insert_company!(%{id: 74, tenant_id: 42, code: "other_company"})
    create_departments_table!()
    insert_department!(101, 73)
    insert_department!(102, 74)

    {:ok, owner} = Tenancy.scope(41)
    {:ok, other} = Tenancy.scope(42)

    assert Company.department_belongs_to_company?(owner, 73, 101)
    refute Company.department_belongs_to_company?(owner, 73, 102)
    refute Company.department_belongs_to_company?(other, 73, 101)
    refute Company.department_belongs_to_company?(owner, 73, -1)

    soft_deleted_company_id = 76

    insert_company!(%{
      id: soft_deleted_company_id,
      code: "soft_deleted_company",
      deleted_at: ~N[2026-08-11 12:00:00]
    })

    insert_department!(103, soft_deleted_company_id)
    refute Company.department_belongs_to_company?(owner, soft_deleted_company_id, 103)
  end

  test "returns a setup state when explicit identity is not provisioned" do
    assert {:error, :not_provisioned} = Company.platform_operator_company()

    insert_tenant!()

    assert {:error, :not_provisioned} = Company.platform_operator_company()
  end

  test "fails closed when the assigned primary company is soft-deleted" do
    insert_tenant!()
    insert_company!(%{deleted_at: ~N[2026-08-11 12:00:00]})
    assign_primary_company!()

    assert {:error, [error]} =
             SchemaContract.verify_invariants(Repo, prefix: temporary_schema!())

    assert error =~ "company 73 for tenant 41 is soft-deleted"
    assert {:error, :invariant_violation} = Company.platform_operator_company()
  end

  test "provisions a tenant and its primary company atomically" do
    assert {:ok, %{tenant: tenant, company: company}} =
             Company.provision_tenant(
               %{name: "Customer tenant"},
               %{name: "Customer company", code: "customer_company"}
             )

    assert company.tenant_id == tenant.id
    assert PrimaryCompanyManager.find_for_tenant(tenant).id == company.id
    assert PrimaryCompanyManager.primary?(company)
  end

  test "requires an explicit transfer when changing a primary company" do
    insert_tenant!()
    insert_company!()
    insert_company!(%{id: 74, code: "successor"})

    {:ok, scope} = Tenancy.scope(41)

    assert {:ok, :assigned} = Company.assign_primary_company(scope, 73)
    assert {:ok, :unchanged} = Company.assign_primary_company(scope, 73)
    assert {:error, {:already_assigned, 73}} = Company.assign_primary_company(scope, 74)
    assert {:ok, :transferred} = Company.transfer_primary_company(scope, 74)
    assert PrimaryCompanyManager.require_for_tenant!(41).id == 74
  end

  test "rejects a primary company owned by another tenant" do
    insert_tenant!()
    insert_tenant!(%{id: 42, name: "Customer", is_platform_operator: false})
    insert_company!()

    {:ok, other_scope} = Tenancy.scope(42)

    assert {:error, {:company_tenant_mismatch, 41}} =
             Company.assign_primary_company(other_scope, 73)
  end

  describe "get_company/2" do
    setup do
      insert_tenant!()
      insert_tenant!(%{id: 42, name: "Customer", is_platform_operator: false})
      insert_company!(%{legal_name: "Bilimbi Industries Sdn. Bhd."})

      {:ok, owner} = Tenancy.scope(41)
      {:ok, other} = Tenancy.scope(42)

      %{owner: owner, other: other}
    end

    test "reads a company owned by the scope's tenant", %{owner: owner} do
      assert {:ok, %Summary{id: 73, tenant_id: 41, name: "Bilimbi Industries"}} =
               Company.get_company(owner, 73)
    end

    test "cannot see another tenant's company", %{other: other} do
      assert {:error, :not_found} = Company.get_company(other, 73)
    end

    test "cannot see a soft-deleted company", %{owner: owner} do
      Ecto.Adapters.SQL.query!(
        Repo,
        "UPDATE companies SET deleted_at = '2026-08-12 12:00:00' WHERE id = 73",
        []
      )

      assert {:error, :not_found} = Company.get_company(owner, 73)
    end

    # Also rejected statically by the type checker; the values are made opaque
    # here so the runtime clause itself is what gets asserted.
    test "cannot be called without a scope", %{owner: owner} do
      for not_a_scope <- [41, nil, Scope.tenant(owner)] do
        assert_raise FunctionClauseError, fn ->
          Company.get_company(opaque(not_a_scope), 73)
        end

        assert_raise FunctionClauseError, fn ->
          Company.assign_primary_company(opaque(not_a_scope), 73)
        end

        assert_raise FunctionClauseError, fn ->
          Company.transfer_primary_company(opaque(not_a_scope), 73)
        end

        assert_raise FunctionClauseError, fn ->
          Company.department_belongs_to_company?(opaque(not_a_scope), 73, 101)
        end
      end
    end
  end

  describe "fetch_tenant_id_for_company/1" do
    test "resolves a live company before a Web scope exists" do
      insert_tenant!()
      insert_company!()

      assert {:ok, 41} = Company.fetch_tenant_id_for_company(73)
    end

    test "fails closed for absent, soft-deleted, and invalid companies" do
      insert_tenant!()
      insert_company!(%{deleted_at: ~N[2026-08-12 12:00:00]})

      for company_id <- [73, 74, 0, -1, nil, "73"] do
        assert {:error, :not_found} = Company.fetch_tenant_id_for_company(company_id)
      end
    end

    test "leaves live-tenant proof to Tenancy.scope/1" do
      insert_tenant!(%{deleted_at: ~N[2026-08-12 12:00:00]})
      insert_company!()

      assert {:ok, 41} = Company.fetch_tenant_id_for_company(73)
      assert {:error, :soft_deleted} = Tenancy.scope(41)
    end
  end

  describe "list_companies/1 and list_tenant_company_ids/1" do
    setup do
      insert_tenant!()
      insert_tenant!(%{id: 42, name: "Customer", is_platform_operator: false})
      insert_company!(%{id: 73, code: "live_a"})
      insert_company!(%{id: 75, code: "live_b"})

      insert_company!(%{
        id: 76,
        code: "soft_deleted",
        deleted_at: ~N[2026-08-11 12:00:00]
      })

      insert_company!(%{id: 74, tenant_id: 42, code: "other_tenant"})

      {:ok, owner} = Tenancy.scope(41)
      {:ok, other} = Tenancy.scope(42)

      %{owner: owner, other: other}
    end

    test "list_companies returns live companies ordered by id", %{owner: owner} do
      assert {:ok, [%Summary{id: 73}, %Summary{id: 75}]} = Company.list_companies(owner)
    end

    test "list_companies excludes soft-deleted and other-tenant companies", %{
      owner: owner,
      other: other
    } do
      assert {:ok, companies} = Company.list_companies(owner)
      refute Enum.any?(companies, &(&1.id == 76))
      refute Enum.any?(companies, &(&1.id == 74))

      assert {:ok, [%Summary{id: 74}]} = Company.list_companies(other)
    end

    test "list_tenant_company_ids includes soft-deleted companies for the tenant", %{
      owner: owner,
      other: other
    } do
      assert {:ok, [73, 75, 76]} = Company.list_tenant_company_ids(owner)
      assert {:ok, [74]} = Company.list_tenant_company_ids(other)
    end

    test "Authz directory exposes only live companies in the tenant", %{
      owner: owner,
      other: other
    } do
      assert AuthzCompanyDirectory.company_ids(owner) == [73, 75]
      assert AuthzCompanyDirectory.company_ids(other) == [74]
      assert AuthzCompanyDirectory.company_in_scope?(owner, 73)
      refute AuthzCompanyDirectory.company_in_scope?(owner, 76)
      refute AuthzCompanyDirectory.company_in_scope?(owner, 74)
    end
  end

  describe "AuthzCompanyDirectory.companies_in_scope/1" do
    setup do
      insert_tenant!()
      insert_tenant!(%{id: 42, name: "Customer", is_platform_operator: false})

      # Names run opposite to ids, so a directory that forgot to sort -- or
      # sorted by id -- fails rather than passing by coincidence.
      insert_company!(%{id: 73, code: "zulu", name: "Zulu Holdings"})
      insert_company!(%{id: 75, code: "alpha", name: "Alpha Trading"})

      # `display_name/1` prefers legal_name, so this row sorts under "M" though
      # its `name` starts with "B". Sorting on the wrong field puts it last.
      insert_company!(%{
        id: 77,
        code: "mid",
        name: "Bravo Supplies",
        legal_name: "Mango Supplies Sdn. Bhd."
      })

      insert_company!(%{
        id: 76,
        code: "gone",
        name: "Aardvark Ltd",
        deleted_at: ~N[2026-08-11 12:00:00]
      })

      # A lowercase initial. Raw binary comparison is codepoint order, so this
      # sorts *below* "Zulu Holdings" unless the directory folds case.
      insert_company!(%{id: 78, code: "emart", name: "eMart Retail"})

      insert_company!(%{id: 74, tenant_id: 42, code: "other", name: "Other Tenant Co"})

      {:ok, owner} = Tenancy.scope(41)
      {:ok, other} = Tenancy.scope(42)

      %{owner: owner, other: other}
    end

    test "names companies the way every other screen names them", %{owner: owner} do
      assert AuthzCompanyDirectory.companies_in_scope(owner) == [
               %{id: 75, name: "Alpha Trading"},
               %{id: 78, name: "eMart Retail"},
               %{id: 77, name: "Mango Supplies Sdn. Bhd."},
               %{id: 73, name: "Zulu Holdings"}
             ]
    end

    test "reports exactly the companies company_ids/1 reports", %{owner: owner, other: other} do
      for scope <- [owner, other] do
        named = AuthzCompanyDirectory.companies_in_scope(scope)

        assert named |> Enum.map(& &1.id) |> Enum.sort() ==
                 Enum.sort(AuthzCompanyDirectory.company_ids(scope))

        # A picker offering an option that fails validation on submit is the
        # bug this pairing exists to prevent.
        assert Enum.all?(named, &AuthzCompanyDirectory.company_in_scope?(scope, &1.id))
      end
    end

    test "excludes soft-deleted and other-tenant companies", %{owner: owner, other: other} do
      owner_ids = owner |> AuthzCompanyDirectory.companies_in_scope() |> Enum.map(& &1.id)

      refute 76 in owner_ids
      refute 74 in owner_ids

      assert AuthzCompanyDirectory.companies_in_scope(other) == [
               %{id: 74, name: "Other Tenant Co"}
             ]
    end
  end

  test "provisions the platform operator and company idempotently" do
    company_attributes = %{name: "Operator company", code: "operator_company"}

    assert {:ok,
            %{
              tenant: tenant,
              company: company,
              tenant_status: :created,
              company_status: :created
            }} = Company.provision_platform_operator("Operator tenant", company_attributes)

    assert company.tenant_id == tenant.id

    assert {:ok,
            %{
              tenant: second_tenant,
              company: second_company,
              tenant_status: :existing,
              company_status: :existing
            }} = Company.provision_platform_operator("Operator tenant", company_attributes)

    assert second_tenant.id == tenant.id
    assert second_company.id == company.id
  end

  test "rolls back operator creation when company validation fails" do
    assert {:error, changeset} =
             Company.provision_platform_operator("Operator tenant", %{name: ""})

    assert {:name, {_message, [validation: :required]}} =
             List.keyfind(changeset.errors, :name, 0)

    assert Tenancy.platform_operator() == nil
  end

  test "create_company slugs a blank code from the name" do
    insert_tenant!()
    {:ok, scope} = Tenancy.scope(41)

    assert {:ok, %Summary{name: "Acme Trading", code: "acme_trading"}} =
             Company.create_company(scope, %{name: "Acme Trading"})
  end

  test "create_company keeps an explicit code" do
    insert_tenant!()
    {:ok, scope} = Tenancy.scope(41)

    assert {:ok, %Summary{code: "ACME"}} =
             Company.create_company(scope, %{name: "Acme Trading", code: "ACME"})
  end

  test "slugging a blank code follows BlbStr::code, not a naive replace" do
    insert_tenant!()
    {:ok, scope} = Tenancy.scope(41)

    # Each of these is a case where "replace every unwanted run with _" and
    # Laravel's `Str::slug($name, "_")` disagree.
    cases = [
      # punctuation is removed, not turned into a separator
      {"A&B Trading", "ab_trading"},
      # dashes flip to the separator
      {"Alpha-Beta", "alpha_beta"},
      # "@" expands to a separated word
      {"me@you", "me_at_you"},
      # accents transliterate rather than vanishing into a separator
      {"Café Ltd", "cafe_ltd"},
      # runs of whitespace collapse, and edges are trimmed
      {"  Spaced   Out  ", "spaced_out"}
    ]

    for {name, expected} <- cases do
      assert {:ok, %Summary{code: ^expected}} = Company.create_company(scope, %{name: name})
    end
  end

  test "create_company rejects an email that is not an address" do
    insert_tenant!()
    {:ok, scope} = Tenancy.scope(41)

    assert {:error, changeset} =
             Company.create_company(scope, %{name: "Bad Email Co", email: "not-an-address"})

    assert {:email, {_message, [validation: :format]}} =
             List.keyfind(changeset.errors, :email, 0)

    assert {:ok, %Summary{}} =
             Company.create_company(scope, %{name: "Good Email Co", email: "ops@example.test"})
  end

  test "create_company validates jurisdiction against known geonames countries" do
    create_geonames_tables!()
    insert_country!(%{iso: "MY", country: "Malaysia"})
    insert_tenant!()
    {:ok, scope} = Tenancy.scope(41)

    assert {:error, changeset} =
             Company.create_company(scope, %{name: "Bad Country Co", jurisdiction: "XX"})

    assert {:jurisdiction, {"must be a valid country ISO code", []}} =
             List.keyfind(changeset.errors, :jurisdiction, 0)

    assert {:ok, %Summary{id: id}} =
             Company.create_company(scope, %{name: "Valid Country Co", jurisdiction: "MY"})

    assert Repo.get(Bilimbi.Core.Company.Schema, id).jurisdiction == "MY"
  end

  defp opaque(value), do: :erlang.element(1, {value})
end
