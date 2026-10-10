defmodule Bilimbi.Core.CompanyLookupTest do
  @moduledoc """
  The cheap company reads (`require_live_company/2`, `identity/2`) answer
  existence and identity from one tenant-scoped query, a relationship never
  carries another company's raw row across the module boundary, and a field
  an operator restricted is withheld from every summary, refused on write
  and skipped by the search for a reader without one of its roles.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.Restricted
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.Summary

  import Bilimbi.Base.Database.TestHelpers
  import Bilimbi.Core.Company.TestFixtures

  @user_id 91
  @company_id 73
  @sibling_id 74

  setup do
    Code.ensure_loaded!(Bilimbi.Base.Authz.TestFixtures)
    create_company_identity_tables!()
    Bilimbi.Base.Authz.TestFixtures.create_authz_tables!()
    Bilimbi.Base.Audit.TestFixtures.create_audit_tables!()
    install_company_authz!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    insert_tenant!()
    insert_company!(%{tax_id: "TAX-98765", email: "hq@bilimbi.test", jurisdiction: "MY"})

    insert_company!(%{
      id: @sibling_id,
      code: "sibling",
      name: "Sibling",
      parent_id: @company_id,
      tax_id: "TAX-11111",
      email: "sibling@bilimbi.test",
      jurisdiction: "AU"
    })

    {:ok, system_scope} = Tenancy.scope(41)

    %{
      reader: Authentication.sign_in(system_scope, @user_id, @company_id),
      system_scope: system_scope
    }
  end

  # The signed-in user restricts `companies.email` to a Finance role nobody
  # holds yet, as the operator page would.
  defp restrict_email!(reader), do: restrict!(reader, "email")

  # Restricts `field` for a Finance role the reader holds: a field is visible
  # until a role the reader holds is named.
  defp restrict!(reader, field) do
    grant!("admin.authz.field.manage")
    {:ok, finance} = Authz.create_role(reader, @company_id, %{name: "Finance", code: "finance"})
    {:ok, _} = Authz.put_field_restriction(reader, "companies", field, [finance.id])
    {:ok, :assigned} = Authz.assign_role(reader, @company_id, :user, @user_id, finance.id)
    finance
  end

  defp drop_role!(reader, role) do
    %{entries: [assignment]} = Authz.list_principal_role_assignments(reader, :user, @user_id)
    {:ok, :unassigned} = Authz.unassign_role(reader, role.id, assignment.id)
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

  describe "a restricted field" do
    test "is withheld from every summary of a holder and names the roles it is restricted for",
         %{reader: reader} do
      finance = restrict_email!(reader)

      assert {:ok, %Summary{email: %Restricted{} = marker, tax_id: "TAX-98765"}} =
               Company.get_company(reader, @company_id)

      assert marker == %Restricted{table_id: "companies", field_id: "email", roles: ["Finance"]}
      assert Company.restricted_field_markers(reader) == %{email: marker}

      assert {:ok, [%Summary{email: %Restricted{}}, %Summary{email: %Restricted{}}]} =
               Company.list_companies(reader)

      assert {:ok, [%Summary{email: %Restricted{}}]} =
               Company.list_child_companies(reader, @company_id)

      assert {:ok, %{company: %Summary{email: %Restricted{}}}} =
               Company.dashboard_summary(reader, @company_id)

      # Without the role the value is back, on the very next call.
      drop_role!(reader, finance)

      assert {:ok, %Summary{email: "hq@bilimbi.test"}} = Company.get_company(reader, @company_id)
      assert Company.restricted_field_markers(reader) == %{}
    end

    test "is refused on update and create whatever the value, and nothing is written", %{
      reader: reader
    } do
      restrict_email!(reader)
      grant!("admin.company.update")

      for attrs <- [
            %{email: "hq@bilimbi.test"},
            %{"email" => "new@bilimbi.test", "name" => "Renamed"}
          ] do
        assert {:error, changeset} = Company.update_company(reader, @company_id, attrs)
        assert errors_on(changeset) == %{email: ["is restricted and cannot be changed"]}
      end

      assert {:ok, %Summary{name: "Renamed", email: %Restricted{}}} =
               Company.update_company(reader, @company_id, %{name: "Renamed"})

      assert {:error, changeset} =
               Company.create_company(reader, %{name: "New Co", email: "new@bilimbi.test"})

      assert errors_on(changeset) == %{email: ["is restricted and cannot be changed"]}

      assert {:ok, %Summary{name: "New Co", email: %Restricted{}}} =
               Company.create_company(reader, %{name: "New Co"})

      # A system scope holds no role, so nothing is restricted for it.
      {:ok, system_scope} = Tenancy.scope(41)

      assert {:ok, %Summary{name: "Renamed", email: "hq@bilimbi.test"}} =
               Company.get_company(system_scope, @company_id)
    end

    test "is not searched for a reader who may not see it", %{reader: reader} do
      assert Company.searchable_columns(reader) == [
               :name,
               :code,
               :legal_name,
               :email,
               :jurisdiction
             ]

      assert {:ok, %{entries: [%{id: @company_id}]}} =
               Company.list_administration_page(reader, search: "hq@bilimbi")

      finance = restrict_email!(reader)
      assert Company.searchable_columns(reader) == [:name, :code, :legal_name, :jurisdiction]

      assert {:ok, %{entries: []}} =
               Company.list_administration_page(reader, search: "hq@bilimbi")

      assert {:ok, %{entries: [%{id: @company_id}]}} =
               Company.list_administration_page(reader, search: "Bilimbi Ind")

      drop_role!(reader, finance)

      assert {:ok, %{entries: [%{id: @company_id}]}} =
               Company.list_administration_page(reader, search: "hq@bilimbi")
    end

    test "jurisdiction reads Restricted in the list, orders nothing and is not searched", %{
      reader: reader
    } do
      desc = [sort_by: :jurisdiction, sort_dir: :desc]

      assert {:ok, %{entries: [%{jurisdiction: "MY"}, %{jurisdiction: "AU"}]}} =
               Company.list_administration_page(reader, desc)

      assert {:ok, %{entries: [%{id: @sibling_id}]}} =
               Company.list_administration_page(reader, search: "AU")

      finance = restrict!(reader, "jurisdiction")

      assert {:ok, %{entries: [first, second]}} = Company.list_administration_page(reader, desc)
      assert [first.name, second.name] == ["Sibling", "Bilimbi Industries"]

      assert %Restricted{field_id: "jurisdiction", roles: ["Finance"]} = first.jurisdiction
      assert %Restricted{} = second.jurisdiction
      assert first.legal_name == nil

      assert {:ok, %{entries: []}} = Company.list_administration_page(reader, search: "AU")

      drop_role!(reader, finance)

      assert {:ok, %{entries: [%{jurisdiction: "MY"}, %{jurisdiction: "AU"}]}} =
               Company.list_administration_page(reader, desc)
    end

    test "the legal name is protected, so no operator can withhold it from the list or a header" do
      companies = Enum.find(Authz.field_restriction_catalog(), &(&1.id == "companies"))

      refute "legal_name" in Enum.map(companies.fields, & &1.id)
    end

    test "the catalog protects the code and status and never offers the key or the name" do
      companies = Enum.find(Authz.field_restriction_catalog(), &(&1.id == "companies"))
      offered = Enum.map(companies.fields, & &1.id)

      assert "email" in offered and "tax_id" in offered and "jurisdiction" in offered
      refute Enum.any?(~w(id name code status parent_id legal_entity_type_id), &(&1 in offered))
      assert companies.record_types == Company.auditable_types()
    end
  end

  defp grant!(capability) do
    {:ok, scope} = Tenancy.scope(41)

    assert {:ok, :stored} =
             Authz.put_principal_capability(scope, @company_id, :user, @user_id, capability, true)
  end

  # The real Company grid tables, so the restriction catalog is the one the
  # operator page offers, beside a minimal Authz snapshot.
  defp install_company_authz! do
    authz =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "core/company", otp_app: :bilimbi_core_company},
          payload: %{
            domains: %{"admin" => "Administrative operations"},
            verbs: ["update", "manage"],
            capabilities: ["admin.company.update", "admin.authz.field.manage"],
            company_directory: Bilimbi.Core.Company.AuthzCompanyDirectory
          }
        }
      ])

    grid =
      Bilimbi.Base.Grid.ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "core/company", otp_app: :bilimbi_core_company},
          payload: Bilimbi.Core.Company.GridTables.tables()
        }
      ])

    ContributionRegistry.put_consumers_for_test!(%{authz: authz, grid: grid}, "company-lookup")
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
