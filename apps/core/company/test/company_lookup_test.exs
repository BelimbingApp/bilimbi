defmodule Bilimbi.Core.CompanyLookupTest do
  @moduledoc """
  The cheap company reads: `require_live_company/2` and `identity/2` answer
  existence and the id, code and display name from one tenant-scoped query
  and never evaluate authorization, and a relationship never carries another
  company's raw row across the module boundary.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.Summary

  import Bilimbi.Core.Company.TestFixtures

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
    %{reader: Authentication.sign_in(system_scope, @user_id, @company_id)}
  end

  test "the identity lookup is one query with no authorization evaluation", %{reader: reader} do
    {found, queries} = capture_queries(fn -> Company.identity(reader, @company_id) end)

    assert {:ok,
            %{id: @company_id, code: "bilimbi_industries", display_name: "Bilimbi Industries"}} =
             found

    assert length(queries) == 1
    refute Enum.any?(queries, &(&1 =~ "base_authz"))
    assert Repo.aggregate(DecisionLog, :count) == 0
    assert {:error, :not_found} = Company.identity(reader, 999)
    assert {:error, :not_found} = Company.identity(reader, "73")
  end

  test "the existence check is one query with no authorization evaluation", %{reader: reader} do
    {found, found_queries} =
      capture_queries(fn -> Company.require_live_company(reader, @company_id) end)

    {missing, _queries} = capture_queries(fn -> Company.require_live_company(reader, 999) end)

    assert found == {:ok, @company_id}
    assert missing == {:error, :not_found}

    assert {{:error, :not_found}, _} =
             capture_queries(fn -> Company.require_live_company(reader, "73") end)

    assert length(found_queries) == 1
    refute Enum.any?(found_queries, &(&1 =~ "base_authz"))
    assert Repo.aggregate(DecisionLog, :count) == 0
  end

  test "relationships carry the other company only as its summary", %{reader: reader} do
    grant!("admin.company.update")
    create_external_access_tables!()
    insert_relationship_type!(11)

    assert {:ok, created} =
             Company.create_relationship(reader, @company_id, %{
               related_company_id: @sibling_id,
               relationship_type_id: 11
             })

    assert {:ok, updated} =
             Company.update_relationship(reader, @company_id, created.id, %{
               effective_to: ~D[2027-01-01]
             })

    for rel <- [created, updated] do
      assert %Ecto.Association.NotLoaded{} = rel.related_company
      assert %Ecto.Association.NotLoaded{} = rel.company
    end

    assert {:ok, [outgoing]} = Company.list_relationships(reader, @company_id)
    assert {:ok, [incoming]} = Company.list_relationships(reader, @sibling_id)

    for {item, other_id} <- [{outgoing, @sibling_id}, {incoming, @company_id}] do
      assert %Summary{id: ^other_id} = item.other_company
      assert %Ecto.Association.NotLoaded{} = item.relationship.related_company
      assert %Ecto.Association.NotLoaded{} = item.relationship.company
    end

    assert %Summary{tax_id: "TAX-11111"} = outgoing.other_company
  end

  defp grant!(capability) do
    {:ok, scope} = Tenancy.scope(41)

    assert {:ok, :stored} =
             Authz.put_principal_capability(scope, @company_id, :user, @user_id, capability, true)
  end

  defp install_company_authz! do
    authz =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "core/company", otp_app: :bilimbi_core_company},
          payload: %{
            domains: %{"admin" => "Administrative operations"},
            verbs: ["update"],
            capabilities: ["admin.company.update"],
            company_directory: Bilimbi.Core.Company.AuthzCompanyDirectory
          }
        }
      ])

    ContributionRegistry.put_consumers_for_test!(%{authz: authz}, "company-lookup")
  end

  defp capture_queries(fun) do
    handler = "company-lookup-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler,
      [:bilimbi, :base, :repo, :query],
      fn _, _, metadata, _ -> send(parent, {:company_lookup_query, metadata.query}) end,
      nil
    )

    result = fun.()
    :telemetry.detach(handler)
    {result, receive_queries([])}
  end

  defp receive_queries(queries) do
    receive do
      {:company_lookup_query, query} -> receive_queries([query | queries])
    after
      20 -> Enum.reverse(queries)
    end
  end
end
