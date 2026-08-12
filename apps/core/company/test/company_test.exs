defmodule Bilimbi.Core.CompanyTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
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

    assert {:ok, :assigned} = Company.assign_primary_company(41, 73)
    assert {:ok, :unchanged} = Company.assign_primary_company(41, 73)
    assert {:error, {:already_assigned, 73}} = Company.assign_primary_company(41, 74)
    assert {:ok, :transferred} = Company.transfer_primary_company(41, 74)
    assert PrimaryCompanyManager.require_for_tenant!(41).id == 74
  end

  test "rejects a primary company owned by another tenant" do
    insert_tenant!()
    insert_tenant!(%{id: 42, name: "Customer", is_platform_operator: false})
    insert_company!()

    assert {:error, {:company_tenant_mismatch, 41}} =
             Company.assign_primary_company(42, 73)
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
             Company.provision_platform_operator("Operator tenant", %{name: "Missing code"})

    assert {:code, {_message, [validation: :required]}} =
             List.keyfind(changeset.errors, :code, 0)

    assert Tenancy.platform_operator() == nil
  end
end
