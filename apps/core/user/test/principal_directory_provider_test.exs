defmodule Bilimbi.Core.User.PrincipalDirectoryProviderTest do
  @moduledoc """
  The provider half of ADR 0011's seam, exercised against the real database.

  `apps/base/principal_directory` can only test the contract on doubles, because
  Base cannot reach Core. This is where the tenant boundary is actually proved.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.PrincipalDirectoryProvider, as: Provider
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup do
    UserFixtures.create_user_tables!()

    CompanyFixtures.insert_tenant!(%{id: 41, name: "Tenant 41"})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73, name: "Ada Lovelace"})

    CompanyFixtures.insert_tenant!(%{id: 42, name: "Tenant 42"})

    CompanyFixtures.insert_company!(%{
      id: 74,
      tenant_id: 42,
      name: "Other Company",
      code: "other_company"
    })

    UserFixtures.insert_user!(%{
      id: 92,
      company_id: 74,
      name: "Grace Hopper",
      email: "grace@example.com"
    })

    {:ok, scope} = Tenancy.scope(41)
    {:ok, other_scope} = Tenancy.scope(42)

    %{scope: scope, other_scope: other_scope}
  end

  test "answers for the :user kind" do
    assert Provider.principal_kind() == :user
  end

  test "names a user inside the scope's tenant", %{scope: scope} do
    assert Provider.names(scope, [91]) == %{91 => "Ada Lovelace"}
  end

  # The half that matters. A plain join would name every id it was handed; this
  # must resolve nothing for a user the scope cannot see, so the caller keeps the
  # row and shows the durable id (#285).
  test "returns nothing for a user in another tenant", %{scope: scope} do
    assert Provider.names(scope, [92]) == %{}
  end

  test "resolves only the visible half of a mixed request", %{scope: scope} do
    assert Provider.names(scope, [91, 92]) == %{91 => "Ada Lovelace"}
  end

  test "the boundary is symmetric, not a property of one tenant", %{other_scope: other} do
    assert Provider.names(other, [92]) == %{92 => "Grace Hopper"}
    assert Provider.names(other, [91]) == %{}
  end

  test "an id that exists nowhere is absent rather than an error", %{scope: scope} do
    assert Provider.names(scope, [404]) == %{}
  end

  test "an empty request is an empty map", %{scope: scope} do
    assert Provider.names(scope, []) == %{}
  end
end
