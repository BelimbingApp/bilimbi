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
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.FieldPolicy
  alias Bilimbi.Base.Authz.Withheld
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
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

  test "a reader without the capability gets the same refusal for the stored value and a wrong one",
       %{reader: reader} do
    grant!("admin.company.update")

    for field <- [:tax_id, :email], key <- [field, Atom.to_string(field)] do
      stored = if field == :tax_id, do: "TAX-98765", else: "hq@bilimbi.test"
      wrong = if field == :tax_id, do: "TAX-00000", else: "guess@bilimbi.test"

      assert {:error, correct} = Company.update_company(reader, @company_id, %{key => stored})
      assert {:error, guess} = Company.update_company(reader, @company_id, %{key => wrong})

      assert errors_on(correct) == %{
               field => ["is withheld from this account and cannot be changed"]
             }

      assert errors_on(correct) == errors_on(guess)
      assert correct.errors == guess.errors
    end

    {:ok, holder} = holder_scope()

    assert {:ok, %Summary{tax_id: "TAX-98765", email: "hq@bilimbi.test"}} =
             Company.get_company(holder, @company_id)
  end

  test "a holder changes the field", %{reader: reader} do
    grant!(@sensitive)

    assert {:ok, %Summary{tax_id: "TAX-00000"}} =
             Company.update_company(reader, @company_id, %{tax_id: "TAX-00000"})

    assert {:ok, %Summary{tax_id: "TAX-00000"}} =
             Company.update_company(reader, @company_id, %{tax_id: "TAX-00000", name: "Again"})
  end

  test "relationships carry the other company only as the redacted summary", %{reader: reader} do
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
      assert %Summary{id: ^other_id, tax_id: %Withheld{}, email: %Withheld{}} = item.other_company
      assert %Ecto.Association.NotLoaded{} = item.relationship.related_company
      assert %Ecto.Association.NotLoaded{} = item.relationship.company
    end

    for value <- ["TAX-11111", "sibling@bilimbi.test", "TAX-98765", "hq@bilimbi.test"] do
      refute inspect([created, updated, outgoing, incoming]) =~ value
    end

    grant!(@sensitive)
    assert {:ok, [holder_view]} = Company.list_relationships(reader, @company_id)
    assert %Summary{tax_id: "TAX-11111"} = holder_view.other_company
  end

  test "a relationship list evaluates the field policy once, however many rows it holds", %{
    reader: reader
  } do
    grant!("admin.company.update")
    create_external_access_tables!()
    insert_relationship_type!(11)
    insert_relationship_type!(12)

    for type_id <- [11, 12] do
      assert {:ok, _} =
               Company.create_relationship(reader, @company_id, %{
                 related_company_id: @sibling_id,
                 relationship_type_id: type_id
               })
    end

    {{:ok, items}, queries} =
      capture_queries(fn -> Company.list_relationships(reader, @company_id) end)

    assert length(items) == 2
    assert Enum.count(queries, &(&1 =~ "base_authz_principal_capabilities")) <= 1
  end

  test "the existence check evaluates no permission and writes no decision", %{reader: reader} do
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

    {_summary, summary_queries} =
      capture_queries(fn -> Company.get_company(reader, @company_id) end)

    assert Enum.any?(summary_queries, &(&1 =~ "base_authz"))
  end

  test "the list search matches email only for a reader who may see it", %{reader: reader} do
    assert {:ok, %{entries: []}} = Company.list_administration_page(reader, search: "hq@bilimbi")

    assert {:ok, %{entries: [%{id: @company_id}]}} =
             Company.list_administration_page(reader, search: "Bilimbi Ind")

    grant!(@sensitive)

    assert {:ok, %{entries: [%{id: @company_id}]}} =
             Company.list_administration_page(reader, search: "hq@bilimbi")
  end

  defp capture_queries(fun) do
    handler = "company-existence-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler,
      [:bilimbi, :base, :repo, :query],
      fn _, _, metadata, _ -> send(parent, {:company_query, metadata.query}) end,
      nil
    )

    result = fun.()
    :telemetry.detach(handler)
    {result, receive_queries([])}
  end

  defp receive_queries(queries) do
    receive do
      {:company_query, query} -> receive_queries([query | queries])
    after
      20 -> Enum.reverse(queries)
    end
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
