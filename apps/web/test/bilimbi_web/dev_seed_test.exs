defmodule BilimbiWeb.DevSeedTest do
  # The seed body `mix bilimbi.dev.seed` and `mix bilimbi.server` share needs
  # the whole installed graph (production seed providers and module sample
  # seeds are discovered from it), which only the host's closure has. The
  # tables are the ones the administrator bootstrap and the sample seeds
  # reach; ConnCase brings the shared ones.
  use BilimbiWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias Mix.Tasks.Bilimbi.Dev.Seed

  @email "ai@agent.my"
  @password "bilimbi-dev"

  setup do
    UserFixtures.create_user_tables!()
    UserFixtures.create_bootstrap_receipt_table!()
    CompanyFixtures.create_department_types_table!()
    CompanyFixtures.create_departments_table!()
    :ok
  end

  test "a fresh database gets reference data, the development login and sample data" do
    # A fresh clone: the Geonames countries are empty until they are imported.
    assert role_codes() == []
    assert Bilimbi.Core.Geonames.get_country("MY") == nil

    assert {:ok, %{administrator: :created, seeds: seeds, module_seeds: module_seeds}} =
             Seed.seed()

    assert Enum.any?(seeds, &(&1.status == :completed))
    assert module_seeds > 0
    assert "core_admin" in role_codes()
    assert {:ok, user} = User.authenticate(@email, @password)
    assert {:ok, company} = Company.platform_operator_company()
    assert {:ok, scope} = Tenancy.scope(company.tenant_id)

    assert [%{role_code: "core_admin"}] =
             Authz.list_principal_role_assignments(scope, :user, user.id).entries
  end

  test "an already seeded database is left as it is" do
    assert {:ok, %{administrator: :created}} = Seed.seed()
    before = snapshot()

    assert {:ok, %{administrator: :already_completed, seeds: seeds}} = Seed.seed()
    assert Enum.all?(seeds, &(&1.status == :skipped))
    assert snapshot() == before
    assert {:ok, _user} = User.authenticate(@email, @password)
  end

  test "identities without a bootstrap receipt are reported, seeded with roles, never promoted" do
    CompanyFixtures.insert_tenant!(%{id: 41, is_platform_operator: false})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!()
    assert role_codes() == []

    assert {:refused, %{reason: :existing_users, seeds: seeds}} = Seed.seed()

    assert Enum.any?(seeds, &(&1.status == :completed))
    assert "core_admin" in role_codes()
    assert is_nil(Tenancy.platform_operator())
    assert {:error, :invalid_credentials} = User.authenticate(@email, @password)
    assert Repo.aggregate("users", :count) == 1
    assert Repo.all(from(b in "bilimbi_user_bootstrap", select: b.id)) == []
  end

  defp role_codes, do: Repo.all(from(r in "base_authz_roles", select: r.code))

  defp snapshot do
    %{
      users: Repo.all(from(u in "users", select: {u.id, u.email, u.password}, order_by: u.id)),
      roles: Repo.all(from(r in "base_authz_roles", select: {r.id, r.code}, order_by: r.id)),
      receipts: Repo.all(from(b in "bilimbi_user_bootstrap", select: b.id))
    }
  end
end
