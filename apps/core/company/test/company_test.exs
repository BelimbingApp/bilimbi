defmodule Bilimbi.Core.CompanyTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.AuthzCompanyDirectory
  alias Bilimbi.Core.Company.IndexEntry
  alias Bilimbi.Core.Company.Page
  alias Bilimbi.Core.Company.PrimaryCompanyManager
  alias Bilimbi.Core.Company.SchemaContract
  alias Bilimbi.Core.Company.Summary

  import Bilimbi.Core.Company.TestFixtures

  setup do
    create_company_identity_tables!()
    :ok
  end

  test "tenant_owner receives tenant-wide company reach without grant_all" do
    authz = Bilimbi.Core.Company.Contributions.contributions().authz
    tenant_owner = authz.roles["tenant_owner"]

    assert "admin.company.tenant-wide.manage" in authz.capabilities
    assert "admin.company.tenant-wide.manage" in tenant_owner.capabilities
    assert "admin.company.create" in tenant_owner.capabilities
    assert "admin.company.delete" in tenant_owner.capabilities
    refute Map.get(tenant_owner, :grant_all, false)
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

  describe "list_companies_page/2" do
    setup do
      insert_tenant!()
      insert_tenant!(%{id: 42, name: "Customer", is_platform_operator: false})

      insert_company!(%{
        id: 73,
        name: "Bilimbi Industries",
        code: "bilimbi_industries",
        jurisdiction: "MY"
      })

      insert_company!(%{
        id: 74,
        parent_id: 73,
        name: "Gamma Trading",
        code: "gamma_trading",
        status: "suspended",
        legal_name: "Gamma Holdings",
        email: "ops@gamma.test",
        jurisdiction: "SG"
      })

      insert_company!(%{
        id: 75,
        tenant_id: 42,
        name: "Gamma Elsewhere",
        code: "gamma_elsewhere",
        status: "suspended",
        legal_name: "Gamma Holdings"
      })

      assign_primary_company!(41, 73)
      {:ok, owner} = Tenancy.scope(41)

      %{owner: owner}
    end

    test "searches, filters, and decorates index rows within the tenant", %{owner: owner} do
      assert %Page{
               entries: [
                 %IndexEntry{
                   id: 74,
                   name: "Gamma Trading",
                   parent_name: "Bilimbi Industries",
                   is_primary: false
                 }
               ],
               page: 1,
               page_size: 25,
               total_entries: 1,
               total_pages: 1
             } =
               Company.list_companies_page(owner,
                 search: "holdings",
                 status: "suspended",
                 sort_by: :jurisdiction,
                 sort_dir: :desc
               )
    end

    test "paginates with the operational list page sizes", %{owner: owner} do
      for number <- 1..26 do
        insert_company!(%{
          id: 100 + number,
          name: "Page Company #{String.pad_leading(to_string(number), 2, "0")}",
          code: "page_company_#{number}"
        })
      end

      page = Company.list_companies_page(owner, page: 2, page_size: 25, sort_by: :name)

      assert %Page{page: 2, page_size: 25, total_entries: 28, total_pages: 2} = page
      assert Enum.map(page.entries, & &1.id) == [124, 125, 126]
    end
  end

  describe "delete_company/2" do
    setup do
      insert_tenant!()
      insert_company!(%{id: 73})
      insert_company!(%{id: 74, code: "branch", name: "Branch"})
      assign_primary_company!(41, 73)
      {:ok, owner} = Tenancy.scope(41)

      %{owner: owner}
    end

    test "soft-deletes a non-primary live company", %{owner: owner} do
      assert :ok = Company.delete_company(owner, 74)
      assert {:error, :not_found} = Company.get_company(owner, 74)
    end

    test "refuses to delete the tenant primary company", %{owner: owner} do
      assert {:error, :primary_company} = Company.delete_company(owner, 73)
      assert {:ok, %Summary{id: 73}} = Company.get_company(owner, 73)
    end
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

  test "updates a company within the scoped tenant" do
    create_geonames_tables!()
    insert_country!(%{iso: "MY", country: "Malaysia"})
    insert_tenant!()
    insert_company!(%{id: 73, name: "Initial Name", code: "initial_code"})
    insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})
    insert_company!(%{id: 74, tenant_id: 42, name: "Other Co", code: "other_co"})

    {:ok, owner} = Tenancy.scope(41)
    {:ok, other} = Tenancy.scope(42)

    assert {:ok, updated} =
             Company.update_company(owner, 73, %{
               name: "Updated Name",
               legal_name: "Updated Legal Name Sdn. Bhd.",
               status: "suspended",
               jurisdiction: "MY",
               email: "info@updated.com",
               website: "https://updated.com",
               scope_activities: ["manufacturing", "distribution"],
               metadata: %{"notes" => "verified"}
             })

    assert updated.id == 73
    assert updated.name == "Updated Name"
    assert updated.legal_name == "Updated Legal Name Sdn. Bhd."
    assert updated.status == "suspended"
    assert updated.jurisdiction == "MY"
    assert updated.email == "info@updated.com"
    assert updated.website == "https://updated.com"
    assert updated.scope_activities == ["manufacturing", "distribution"]
    assert updated.metadata == %{"notes" => "verified"}

    assert {:error, :not_found} = Company.update_company(other, 73, %{name: "Hacked"})
    assert {:error, :not_found} = Company.update_company(owner, 9999, %{name: "Nonexistent"})

    # Validation errors
    assert {:error, changeset} = Company.update_company(owner, 73, %{status: "invalid_status"})
    assert {:status, _} = List.keyfind(changeset.errors, :status, 0)
  end

  test "lists child companies and checks primary designation" do
    insert_tenant!()
    insert_company!(%{id: 73, name: "Parent Co", code: "parent_co"})
    insert_company!(%{id: 74, parent_id: 73, name: "Child Co 1", code: "child_co_1"})
    insert_company!(%{id: 75, parent_id: 73, name: "Child Co 2", code: "child_co_2"})

    insert_company!(%{
      id: 76,
      parent_id: 73,
      name: "Deleted Child",
      code: "deleted_child",
      deleted_at: ~N[2026-08-11 12:00:00]
    })

    assign_primary_company!()

    {:ok, owner} = Tenancy.scope(41)

    assert {:ok, children} = Company.list_child_companies(owner, 73)
    assert Enum.map(children, & &1.id) == [74, 75]

    assert Company.primary_company?(owner, 73) == true
    assert Company.primary_company?(owner, 74) == false
  end

  defp opaque(value), do: :erlang.element(1, {value})
end
