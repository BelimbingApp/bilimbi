defmodule Bilimbi.Core.UserArchivedCompanyTest do
  @moduledoc """
  An account in an archived company is read-only: Core User refuses every
  write into that company with `:company_archived` while the account stays
  readable and its stored credential never changes (no legacy upgrade on
  sign-in, no public password reset). Moving an account into one is
  `Bilimbi.Core.User.AdminAffiliationTest`.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Summary

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

  describe "credentials" do
    test "a legacy hash is not rewritten on a correct sign-in" do
      legacy_hash = legacy_password_hash("legacy-password")

      insert_user!(%{
        id: 96,
        company_id: @archived,
        email: "legacy@example.com",
        password_hash: legacy_hash
      })

      assert {:ok, %Summary{id: 96}} = User.authenticate("legacy@example.com", "legacy-password")
      assert stored_password(96) == legacy_hash
    end

    test "a reset is neither delivered nor redeemable once the company is archived" do
      CompanyFixtures.insert_company!(%{id: 75, tenant_id: 41, name: "Closing", code: "closing"})
      old_hash = password_hash("old-password")

      insert_user!(%{
        id: 97,
        company_id: 75,
        email: "closing@example.com",
        password_hash: old_hash
      })

      deliver = fn _user, token ->
        send(self(), {:password_reset, token})
        :ok
      end

      assert :ok = User.request_password_reset("closing@example.com", deliver)
      assert_receive {:password_reset, token}

      Ecto.Adapters.SQL.query!(Repo, "UPDATE companies SET status = 'archived' WHERE id = 75")

      assert :ok =
               User.request_password_reset("closing@example.com", deliver, throttle_seconds: 0)

      refute_receive {:password_reset, _token}

      assert {:error, :invalid_or_expired_token} =
               User.reset_password("closing@example.com", token, "new-password")

      assert stored_password(97) == old_hash
    end
  end
end
