defmodule Bilimbi.Core.UserArchivedCompanyTest do
  @moduledoc """
  An account in an archived company is read-only: Core User refuses every
  write into that company with `:company_archived` while the account stays
  readable. Moving an account into one is `Bilimbi.Core.User.AdminAffiliationTest`.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User

  import Bilimbi.Core.User.TestFixtures

  @active 73
  @archived 74

  setup do
    create_user_tables!()

    CompanyFixtures.insert_tenant!(%{id: 41, name: "Tenant A"})
    CompanyFixtures.insert_company!(%{id: @active, tenant_id: 41, name: "Active", code: "a"})

    CompanyFixtures.insert_company!(%{
      id: @archived,
      tenant_id: 41,
      name: "Archived",
      code: "archived",
      status: "archived"
    })

    insert_user!(%{id: 95, company_id: @archived, email: "archived@example.com"})

    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  test "the account is readable", %{scope: scope} do
    assert {:ok, %{id: 95}} = User.get_user(scope, @archived, 95)
    assert {:ok, [%{id: 95}]} = User.list_company_users(scope, @archived)
  end

  test "no account can be created, changed or deleted in it", %{scope: scope} do
    assert {:error, :company_archived} =
             User.create_user(scope, @archived, %{
               name: "New",
               email: "new@example.com",
               password: "correct horse"
             })

    assert {:error, :company_archived} =
             User.update_user(scope, @archived, 95, %{name: "Renamed"})

    assert {:error, :company_archived} = User.delete_user(scope, @archived, 95)
    assert {:ok, %{name: name}} = User.get_user(scope, @archived, 95)
    refute name == "Renamed"
  end
end
