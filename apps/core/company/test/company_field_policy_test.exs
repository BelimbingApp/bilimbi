defmodule Bilimbi.Core.CompanyFieldPolicyTest do
  @moduledoc """
  Tax ID and email are the company fields a reader needs
  `admin.company.sensitive.view` to see. Every read model this module
  returns withholds them from anyone else, the update path refuses a change
  to them, and the list search does not match them (#777).
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.Authz.FieldPolicy
  alias Bilimbi.Base.Authz.Withheld
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.Summary

  import Bilimbi.Base.Database.TestHelpers
  import Bilimbi.Core.Company.TestFixtures

  @sensitive "admin.company.sensitive.view"
  @user_id 91
  @company_id 73
  @sibling_id 74

  setup do
    Code.ensure_loaded!(Bilimbi.Base.Authz.TestFixtures)
    create_company_identity_tables!()
    Bilimbi.Base.Authz.TestFixtures.create_authz_tables!()
    install_company_authz!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    insert_tenant!()
    insert_company!(%{tax_id: "TAX-98765", email: "hq@bilimbi.test"})

    insert_company!(%{
      id: @sibling_id,
      code: "sibling",
      name: "Sibling",
      parent_id: @company_id,
      tax_id: "TAX-11111",
      email: "sibling@bilimbi.test"
    })

    {:ok, system_scope} = Tenancy.scope(41)

    %{
      system_scope: system_scope,
      reader: Authentication.sign_in(system_scope, @user_id, @company_id)
    }
  end

  test "the policy names tax_id and email under one capability" do
    assert FieldPolicy.fields(Summary.field_policy()) == [:tax_id, :email]
    assert FieldPolicy.capabilities(Summary.field_policy()) == [@sensitive]
  end

  test "a holder reads the values and has nothing withheld", %{reader: reader} do
    grant!(@sensitive)

    assert Company.withheld_fields(reader) == []

    assert {:ok, %Summary{tax_id: "TAX-98765", email: "hq@bilimbi.test"}} =
             Company.get_company(reader, @company_id)

    assert {:ok, [%Summary{tax_id: "TAX-98765"}, %Summary{tax_id: "TAX-11111"}]} =
             Company.list_companies(reader)
  end

  test "every read model withholds both fields from a reader without the capability", %{
    reader: reader
  } do
    withheld = %Withheld{capability: @sensitive}

    assert Company.withheld_fields(reader) == [:tax_id, :email]

    assert {:ok, %Summary{name: "Bilimbi Industries", tax_id: ^withheld, email: ^withheld}} =
             Company.get_company(reader, @company_id)

    assert {:ok, [%Summary{tax_id: ^withheld, email: ^withheld}, %Summary{tax_id: ^withheld}]} =
             Company.list_companies(reader)

    assert {:ok, [%Summary{id: @sibling_id, tax_id: ^withheld}]} =
             Company.list_child_companies(reader, @company_id)

    assert {:ok, %{company: %Summary{tax_id: ^withheld, email: ^withheld}}} =
             Company.dashboard_summary(reader, @company_id)

    # The rest of the record is untouched.
    assert {:ok, %Summary{code: "bilimbi_industries", status: "active"}} =
             Company.get_company(reader, @company_id)
  end

  test "a system scope names nobody and is withheld the fields", %{system_scope: system_scope} do
    assert Company.withheld_fields(system_scope) == [:tax_id, :email]

    assert {:ok, %Summary{tax_id: %Withheld{}, email: %Withheld{}}} =
             Company.get_company(system_scope, @company_id)
  end

  test "a reader without the capability cannot change a withheld field", %{reader: reader} do
    grant!("admin.company.update")

    assert {:error, changeset} =
             Company.update_company(reader, @company_id, %{tax_id: "TAX-00000"})

    assert errors_on(changeset) == %{
             tax_id: ["is withheld from this account and cannot be changed"]
           }

    assert {:error, changeset} =
             Company.update_company(reader, @company_id, %{
               "email" => "new@bilimbi.test",
               "name" => "Renamed"
             })

    assert errors_on(changeset) == %{
             email: ["is withheld from this account and cannot be changed"]
           }

    # Other facts still save, and the summary that comes back keeps the fields withheld.
    assert {:ok, %Summary{name: "Renamed", tax_id: %Withheld{}}} =
             Company.update_company(reader, @company_id, %{name: "Renamed"})

    # Nothing of the refused writes landed, not even their permitted part.
    # (Grants accumulate on a user, so the holder is asked last.)
    {:ok, holder} = holder_scope()

    assert {:ok, %Summary{name: "Renamed", tax_id: "TAX-98765", email: "hq@bilimbi.test"}} =
             Company.get_company(holder, @company_id)
  end

  test "a holder changes the field, and sending the stored value back is not a change", %{
    reader: reader
  } do
    grant!(@sensitive)

    assert {:ok, %Summary{tax_id: "TAX-00000"}} =
             Company.update_company(reader, @company_id, %{tax_id: "TAX-00000"})

    {:ok, system_scope} = Tenancy.scope(41)
    without = Authentication.sign_in(system_scope, @user_id, @sibling_id)
    grant!("admin.company.update", @sibling_id)

    assert {:ok, %Summary{tax_id: %Withheld{}}} =
             Company.update_company(without, @company_id, %{tax_id: "TAX-00000", name: "Still"})
  end

  test "the list search matches email only for a reader who may see it", %{reader: reader} do
    assert {:ok, %{entries: []}} = Company.list_administration_page(reader, search: "hq@bilimbi")

    assert {:ok, %{entries: [%{id: @company_id}]}} =
             Company.list_administration_page(reader, search: "Bilimbi Ind")

    grant!(@sensitive)

    assert {:ok, %{entries: [%{id: @company_id}]}} =
             Company.list_administration_page(reader, search: "hq@bilimbi")
  end

  defp holder_scope do
    {:ok, system_scope} = Tenancy.scope(41)
    grant!(@sensitive)
    {:ok, Authentication.sign_in(system_scope, @user_id, @company_id)}
  end

  defp grant!(capability, company_id \\ @company_id) do
    {:ok, scope} = Tenancy.scope(41)

    assert {:ok, :stored} =
             Authz.put_principal_capability(scope, company_id, :user, @user_id, capability, true)
  end

  defp install_company_authz! do
    authz =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "core/company", otp_app: :bilimbi_core_company},
          payload: %{
            domains: %{"admin" => "Administrative operations"},
            verbs: ["view", "update"],
            capabilities: [@sensitive, "admin.company.update"],
            company_directory: Bilimbi.Core.Company.AuthzCompanyDirectory
          }
        }
      ])

    ContributionRegistry.put_consumers_for_test!(%{authz: authz}, "company-field-policy")
  end
end
