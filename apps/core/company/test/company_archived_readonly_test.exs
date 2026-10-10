defmodule Bilimbi.Core.CompanyArchivedReadonlyTest do
  @moduledoc """
  An archived company is read-only everywhere in Core Company: its own facts,
  its departments, relationships, external accesses and the primary-company
  assignment refuse to change with one named error, while every read keeps
  answering. Soft deletion stays a separate fact (`:not_found`).
  """

  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.AuthzCompanyDirectory
  alias Bilimbi.Core.Company.LiveCompanyProof

  import Bilimbi.Core.Company.TestFixtures

  @active 73
  @archived 74
  @deleted 75

  setup do
    create_company_identity_tables!()
    Bilimbi.Base.Authz.TestFixtures.create_authz_tables!()
    create_departments_table!()
    create_legal_entity_types_table!()
    create_external_access_tables!()

    insert_tenant!(%{id: 41, is_platform_operator: true})

    insert_company!(%{id: @active, tenant_id: 41, name: "Active", code: "active"})

    insert_company!(%{
      id: @archived,
      tenant_id: 41,
      name: "Archived",
      code: "archived",
      status: "archived"
    })

    insert_company!(%{
      id: @deleted,
      tenant_id: 41,
      name: "Deleted",
      code: "deleted",
      deleted_at: ~N[2026-08-11 12:00:00]
    })

    {:ok, scope} = Tenancy.scope(41)
    %{scope: scope}
  end

  describe "the guard" do
    test "require_writable_company/2 tells archived apart from missing", %{scope: scope} do
      assert {:ok, @active} = Company.require_writable_company(scope, @active)
      assert {:error, :company_archived} = Company.require_writable_company(scope, @archived)
      assert {:error, :not_found} = Company.require_writable_company(scope, @deleted)
      assert {:error, :not_found} = Company.require_writable_company(scope, 999)
      assert {:error, :not_found} = Company.require_writable_company(scope, "73")
    end

    test "lock_writable_company/2 refuses the archived row under the lock", %{scope: scope} do
      assert {:ok, {:ok, %LiveCompanyProof{id: @active}}} =
               Repo.transaction(fn -> Company.lock_writable_company(scope, @active) end)

      assert {:ok, {:error, :company_archived}} =
               Repo.transaction(fn -> Company.lock_writable_company(scope, @archived) end)

      assert {:ok, {:error, :not_found}} =
               Repo.transaction(fn -> Company.lock_writable_company(scope, @deleted) end)
    end

    test "archived?/1 reads the summary's status", %{scope: scope} do
      {:ok, active} = Company.get_company(scope, @active)
      {:ok, archived} = Company.get_company(scope, @archived)

      refute Company.archived?(active)
      assert Company.archived?(archived)
    end

    test "the Authz company directory answers the same rule", %{scope: scope} do
      assert :ok = AuthzCompanyDirectory.company_writable(scope, @active)

      assert {:error, :company_archived} =
               AuthzCompanyDirectory.company_writable(scope, @archived)

      assert {:error, :company_not_found} =
               AuthzCompanyDirectory.company_writable(scope, @deleted)

      # Reads still see it: an archived company stays in scope.
      assert AuthzCompanyDirectory.company_in_scope?(scope, @archived)
    end
  end

  describe "the company's own facts" do
    test "reads keep answering", %{scope: scope} do
      assert {:ok, %{status: "archived"}} = Company.get_company(scope, @archived)
      assert {:ok, %{display_name: "Archived"}} = Company.identity(scope, @archived)
      assert {:ok, @archived} = Company.require_live_company(scope, @archived)
      assert {:ok, ids} = Company.list_live_company_ids(scope)
      assert @archived in ids
    end

    test "update_company/3 is refused by name and writes nothing", %{scope: scope} do
      assert {:error, :company_archived} =
               Company.update_company(scope, @archived, %{name: "Renamed"})

      assert {:ok, %{name: "Archived"}} = Company.get_company(scope, @archived)

      assert {:ok, %{name: "Renamed"}} =
               Company.update_company(scope, @active, %{name: "Renamed"})
    end

    test "no lifecycle operation leaves archived", %{scope: _scope} do
      assert Company.lifecycle_operations("archived") == []
    end

    test "the primary company cannot be moved to an archived company", %{scope: scope} do
      assign_primary_company!(41, @active)
      assert {:error, :company_archived} = Company.transfer_primary_company(scope, @archived)
      assert Company.primary_company?(scope, @active)
    end
  end

  describe "departments" do
    test "are readable but not writable", %{scope: scope} do
      insert_department_with_type!(101, @archived)

      assert {:ok, [%{id: 101}]} = Company.list_departments(scope, @archived)

      assert {:error, :company_archived} =
               Company.create_department(scope, @archived, %{name: "Finance"})

      assert {:error, :company_archived} =
               Company.update_department_status(scope, @archived, 101, "suspended")

      assert {:error, :company_archived} =
               Company.update_department_head(scope, @archived, 101, nil)

      assert {:error, :company_archived} = Company.delete_department(scope, @archived, 101)
      assert {:ok, [%{id: 101}]} = Company.list_departments(scope, @archived)
    end
  end

  describe "relationships" do
    setup do
      insert_relationship_type!(11)
      :ok
    end

    test "an archived owner refuses every write and keeps its rows readable", %{scope: scope} do
      insert_relationship!(21, @archived, @active)

      assert {:ok, [%{id: 21}]} = Company.list_relationships(scope, @archived)

      assert {:error, :company_archived} =
               Company.create_relationship(scope, @archived, %{
                 related_company_id: @active,
                 relationship_type_id: 11
               })

      assert {:error, :company_archived} =
               Company.update_relationship(scope, @archived, 21, %{effective_to: ~D[2026-12-31]})

      assert {:error, :company_archived} = Company.delete_relationship(scope, @archived, 21)
      assert {:ok, [%{id: 21}]} = Company.list_relationships(scope, @archived)
    end

    test "the live side cannot change or remove a relationship with an archived company",
         %{scope: scope} do
      insert_relationship!(21, @archived, @active)
      insert_relationship!(22, @active, @archived)

      for id <- [21, 22] do
        assert {:error, :related_company_archived} =
                 Company.update_relationship(scope, @active, id, %{effective_to: ~D[2026-12-31]})

        assert {:error, :related_company_archived} =
                 Company.delete_relationship(scope, @active, id)
      end

      assert {:ok, rows} = Company.list_relationships(scope, @archived)
      assert rows |> Enum.map(& &1.id) |> Enum.sort() == [21, 22]
    end

    test "an archived related company is refused and never offered", %{scope: scope} do
      assert {:error, :related_company_archived} =
               Company.create_relationship(scope, @active, %{
                 related_company_id: @archived,
                 relationship_type_id: 11
               })

      assert {:ok, offered} = Company.list_available_related_companies(scope, @active)
      refute Enum.any?(offered, &(&1.id == @archived))
    end
  end

  describe "external accesses" do
    test "are readable but not writable", %{scope: scope} do
      insert_relationship_type!(11)
      insert_relationship!(21, @archived, @active)

      assert {:error, :company_archived} =
               Company.create_external_access(scope, @archived, %{
                 relationship_id: 21,
                 user_id: 91,
                 access_level: "view"
               })

      assert {:ok, []} = Company.list_external_accesses(scope, @archived)

      assert {:error, :company_archived} =
               Company.revoke_external_access(scope, @archived, 1)
    end
  end
end
