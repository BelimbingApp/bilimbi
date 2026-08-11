defmodule Bilimbi.Core.CompanyTest do
  use Bilimbi.Base.DataCase, async: true

  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.PrimaryCompanyManager
  alias Bilimbi.Core.Company.Summary

  import Bilimbi.Core.CompanyFixtures

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

  test "returns a setup state when explicit identity is not provisioned" do
    assert {:error, :not_provisioned} = Company.platform_operator_company()

    insert_tenant!()

    assert {:error, :not_provisioned} = Company.platform_operator_company()
  end

  test "fails closed when the assigned primary company is soft-deleted" do
    insert_tenant!()
    insert_company!(%{deleted_at: ~N[2026-08-11 12:00:00]})
    assign_primary_company!()

    assert {:error, :invariant_violation} = Company.platform_operator_company()
  end
end
