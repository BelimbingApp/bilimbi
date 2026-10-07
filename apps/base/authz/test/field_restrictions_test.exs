defmodule Bilimbi.Base.Authz.FieldRestrictionsTest do
  @moduledoc """
  Field access is the operator's call: a restriction names a catalog field
  and the roles that still see it, and everyone else in the tenant reads the
  field as `Restricted`, may not write it, and loses the grid column. The
  catalog never offers a field a module protected or every reader needs.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.FieldRestrictionSummary
  alias Bilimbi.Base.Authz.Restricted
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures

  import Bilimbi.Base.Authz.TestFixtures
  import Ecto.Query, only: [from: 2]

  defmodule Record do
    @moduledoc false
    defstruct [:id, :name, :code, :tax_id, :email]
  end

  defmodule Other do
    @moduledoc false
    defstruct [:id]
  end

  @manage "admin.authz.field.manage"
  @view "admin.test.record.view"

  # A grid snapshot as the registry holds it: plain data Base Authz reads
  # without depending on Base Grid. `code` is protected by its owner, `name`
  # is the label field, `id` the key, `parent_id` hidden and joined.
  @grid %{
    tables: %{
      "records" => %{
        id: "records",
        label: "Records",
        capability: @view,
        key: "id",
        label_field: "name",
        time_field: nil,
        record_types: ["Test.Record", "App\\Test\\Record"],
        field_order: ~w(id name code tax_id email parent_id),
        fields: %{
          "id" => %{id: "id", label: "ID", hidden: false, protected: false},
          "name" => %{id: "name", label: "Name", hidden: false, protected: false},
          "code" => %{id: "code", label: "Code", hidden: false, protected: true},
          "tax_id" => %{id: "tax_id", label: "Tax ID", hidden: false, protected: false},
          "email" => %{id: "email", label: "Email", hidden: false, protected: false},
          "parent_id" => %{id: "parent_id", label: "Parent", hidden: true, protected: false}
        },
        links: %{
          "parent" => %{id: "parent", to: "records", kind: :one, on: {"parent_id", "id"}}
        }
      },
      "notes" => %{
        id: "notes",
        label: "Notes",
        capability: @view,
        key: "id",
        label_field: "body",
        time_field: nil,
        record_types: [],
        field_order: ~w(id body),
        fields: %{
          "id" => %{id: "id", label: "ID", hidden: false, protected: false},
          "body" => %{id: "body", label: "Body", hidden: false, protected: false}
        },
        links: %{}
      }
    }
  }

  setup do
    create_authz_tables!()
    Bilimbi.Base.Audit.TestFixtures.create_audit_tables!()
    install_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    scope = TenancyFixtures.scope()
    operator = Authentication.sign_in(scope, 7, 10)
    assert {:ok, :stored} = Authz.put_principal_capability(scope, 10, :user, 7, @manage, true)

    {:ok, viewer} = Authz.create_role(operator, 10, %{name: "Viewer", code: "viewer"})
    {:ok, finance} = Authz.create_role(operator, 10, %{name: "Finance", code: "finance"})

    %{scope: scope, operator: operator, viewer: viewer, finance: finance}
  end

  defp install_registry! do
    install_test_registry!()
    snapshot = ContributionRegistry.snapshot!()

    ContributionRegistry.put_snapshot_for_test!(
      put_in(snapshot.consumers.grid, @grid)
      |> put_in(
        [:consumers, :authz],
        Map.update!(snapshot.consumers.authz, :capabilities, &Enum.sort([@manage | &1]))
      )
    )
  end

  defp record, do: %Record{id: 1, name: "Acme", code: "acme", tax_id: "TAX-1", email: "a@x.test"}

  defp reader(scope, user_id), do: Authentication.sign_in(scope, user_id, 10)

  describe "the catalog" do
    test "offers restrictable fields only, never protected, key, label, hidden or joined ones" do
      # Notes has only its key and its label, so it is not offered at all.
      assert [%{id: "records", label: "Records"} = records] = Authz.field_restriction_catalog()
      assert Enum.map(records.fields, & &1.id) == ~w(tax_id email)
      assert records.record_types == ["Test.Record", "App\\Test\\Record"]
    end
  end

  describe "setting and removing" do
    test "needs admin.authz.field.manage", %{scope: scope, viewer: viewer} do
      bystander = reader(scope, 8)

      assert {:error, :forbidden} =
               Authz.put_field_restriction(bystander, "records", "tax_id", [viewer.id])

      assert {:error, :forbidden} = Authz.list_field_restrictions(bystander)
      assert {:error, :forbidden} = Authz.remove_field_restriction(bystander, 1)
      assert {:error, :forbidden} = Authz.put_field_restriction(scope, "records", "tax_id", [])
    end

    test "refuses a field outside the catalog and a role outside the scope", %{
      operator: operator,
      viewer: viewer
    } do
      assert {:error, :not_restrictable} =
               Authz.put_field_restriction(operator, "records", "code", [viewer.id])

      assert {:error, :not_restrictable} =
               Authz.put_field_restriction(operator, "records", "parent_id", [viewer.id])

      assert {:error, :not_restrictable} =
               Authz.put_field_restriction(operator, "ledger", "amount", [viewer.id])

      assert {:error, {:unknown_roles, [999_999]}} =
               Authz.put_field_restriction(operator, "records", "tax_id", [viewer.id, 999_999])

      assert {:ok, []} = Authz.list_field_restrictions(operator)
    end

    test "creates, lists with labels and role names, replaces roles, removes, and records who did it",
         %{operator: operator, viewer: viewer, finance: finance} do
      assert {:ok, %FieldRestrictionSummary{} = created} =
               Authz.put_field_restriction(operator, "records", "tax_id", [finance.id])

      assert created.table_label == "Records"
      assert created.field_label == "Tax ID"
      assert created.role_ids == [finance.id]
      assert created.role_names == ["Finance"]

      assert {:ok, %FieldRestrictionSummary{id: id}} =
               Authz.put_field_restriction(operator, "records", "tax_id", [viewer.id, finance.id])

      assert id == created.id

      assert {:ok, [%FieldRestrictionSummary{role_names: ["Finance", "Viewer"]}]} =
               Authz.list_field_restrictions(operator)

      assert {:ok, :removed} = Authz.remove_field_restriction(operator, id)
      assert {:ok, :not_found} = Authz.remove_field_restriction(operator, id)
      assert {:ok, []} = Authz.list_field_restrictions(operator)

      {:ok, actions} = Audit.list_actions(operator)
      summaries = Enum.map(actions, & &1.payload["summary"])
      assert Enum.any?(summaries, &(&1 == "Restricted records.tax_id to Finance"))
      assert Enum.any?(summaries, &(&1 == "Restricted records.tax_id to Finance, Viewer"))
      assert Enum.any?(summaries, &(&1 == "Unrestricted records.tax_id"))

      assert Enum.all?(actions, &(&1.actor_type == "user" and &1.actor_id == 7))
    end

    test "putting over a row that already exists replaces its roles and leaves one row", %{
      operator: operator,
      scope: scope,
      viewer: viewer,
      finance: finance
    } do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      {1, nil} =
        Bilimbi.Base.Repo.insert_all(
          Bilimbi.Base.Authz.FieldRestriction,
          [
            %{
              tenant_id: Bilimbi.Base.Tenancy.Scope.tenant_id(scope),
              table_id: "records",
              field_id: "tax_id",
              created_at: now,
              updated_at: now
            }
          ]
        )

      for roles <- [[finance.id], [viewer.id, finance.id]] do
        assert {:ok, %FieldRestrictionSummary{role_ids: role_ids}} =
                 Authz.put_field_restriction(operator, "records", "tax_id", roles)

        assert role_ids == Enum.sort(roles)
      end

      assert {:ok, [%FieldRestrictionSummary{field_id: "tax_id"}]} =
               Authz.list_field_restrictions(operator)
    end

    test "another tenant neither sees nor removes it", %{operator: operator, finance: finance} do
      assert {:ok, restriction} =
               Authz.put_field_restriction(operator, "records", "tax_id", [finance.id])

      # Tenant 2 has no companies in the test directory, so nobody there can
      # hold the capability; what it can be shown is nothing of tenant 1's.
      other_reader = Authentication.sign_in(TenancyFixtures.scope(2), 9, 20)

      assert {:error, :forbidden} = Authz.list_field_restrictions(other_reader)
      assert {:error, :forbidden} = Authz.remove_field_restriction(other_reader, restriction.id)
      assert Authz.restricted_fields(other_reader) == %{}
      assert record() == Authz.redact(other_reader, "records", record())
    end
  end

  describe "reading" do
    test "a holder of an allowed role sees the value; everyone else gets Restricted naming the roles",
         %{scope: scope, operator: operator, finance: finance} do
      assert {:ok, _} = Authz.put_field_restriction(operator, "records", "tax_id", [finance.id])

      without = reader(scope, 8)
      assert Authz.restricted_fields(without) == %{"records" => %{"tax_id" => ["Finance"]}}
      assert Authz.restricted_fields(without, "records") == ["tax_id"]

      assert %Record{tax_id: %Restricted{} = marker, email: "a@x.test"} =
               Authz.redact(without, "records", record())

      assert marker == %Restricted{table_id: "records", field_id: "tax_id", roles: ["Finance"]}
      assert Restricted.requirement(marker) == "the Finance role"

      assert [%Record{tax_id: %Restricted{}}, %Record{tax_id: %Restricted{}}] =
               Authz.redact(without, "records", [record(), record()])

      # Another table is untouched, and so is a record that lacks the field.
      assert record() == Authz.redact(without, "notes", record())
      assert %Other{id: 1} == Authz.redact(without, "records", %Other{id: 1})

      assert {:ok, :assigned} = Authz.assign_role(operator, 10, :user, 8, finance.id)
      holder = reader(scope, 8)
      assert Authz.restricted_fields(holder) == %{}
      assert record() == Authz.redact(holder, "records", record())

      # No decision is logged for either reader: nothing was attempted. (The
      # operator's own capability check is the one row.)
      assert Repo.aggregate(from(log in DecisionLog, where: log.actor_id == 8), :count) == 0
    end

    test "a restriction with no role hides the field from everyone, and a system scope sees nothing restricted",
         %{scope: scope, operator: operator} do
      assert {:ok, _} = Authz.put_field_restriction(operator, "records", "email", [])

      assert %Record{email: %Restricted{roles: []} = marker} =
               Authz.redact(operator, "records", record())

      assert Restricted.requirement(marker) == nil
      assert Authz.restricted_fields(scope, "records") == ["email"]
    end

    test "removing the restriction or the role is seen on the very next read", %{
      scope: scope,
      operator: operator,
      finance: finance
    } do
      assert {:ok, restriction} =
               Authz.put_field_restriction(operator, "records", "tax_id", [finance.id])

      assert {:ok, :assigned} = Authz.assign_role(operator, 10, :user, 8, finance.id)
      holder = reader(scope, 8)
      assert Authz.restricted_fields(holder, "records") == []

      %{entries: [assignment]} = Authz.list_principal_role_assignments(operator, :user, 8)
      assert {:ok, :unassigned} = Authz.unassign_role(operator, finance.id, assignment.id)
      assert Authz.restricted_fields(holder, "records") == ["tax_id"]

      assert {:ok, :removed} = Authz.remove_field_restriction(operator, restriction.id)
      assert Authz.restricted_fields(holder, "records") == []
    end

    test "reaches the audit views through the table's record types", %{
      scope: scope,
      operator: operator,
      finance: finance
    } do
      assert {:ok, _} = Authz.put_field_restriction(operator, "records", "tax_id", [finance.id])

      assert Authz.withheld_fields_by_type(reader(scope, 8), [
               "Test.Record",
               "App\\Test\\Record",
               "Other"
             ]) == %{"Test.Record" => ["tax_id"], "App\\Test\\Record" => ["tax_id"]}

      assert Authz.withheld_fields_by_type(reader(scope, 8), ["Other"]) == %{}
    end
  end

  describe "writing" do
    test "any attempt to set a restricted field is refused the same way, whatever the value", %{
      scope: scope,
      operator: operator,
      finance: finance
    } do
      assert {:ok, _} = Authz.put_field_restriction(operator, "records", "tax_id", [finance.id])
      without = reader(scope, 8)
      types = %{tax_id: :string, email: :string, name: :string}
      data = %{tax_id: "TAX-1", email: "a@x.test", name: "Acme"}

      for attrs <- [%{tax_id: "TAX-1"}, %{"tax_id" => "TAX-2", "name" => "Renamed"}] do
        changeset =
          {data, types}
          |> Ecto.Changeset.cast(attrs, [:tax_id, :email, :name])
          |> Authz.refuse_restricted_attempts(without, "records", attrs)

        refute changeset.valid?
        assert changeset.errors == [tax_id: {"is restricted and cannot be changed", []}]
      end

      changeset =
        {data, types}
        |> Ecto.Changeset.cast(%{email: "b@x.test"}, [:tax_id, :email, :name])
        |> Authz.refuse_restricted_attempts(without, "records", %{email: "b@x.test"})

      assert changeset.valid?
    end
  end

  describe "the marker" do
    test "renders as the word, never as a value, and is not a string" do
      marker = %Restricted{table_id: "records", field_id: "tax_id", roles: ["A", "B"]}

      assert Restricted.restricted?(marker)
      refute Restricted.restricted?("TAX-1")
      assert Phoenix.HTML.Safe.to_iodata(marker) |> IO.iodata_to_binary() == "Restricted"
      assert Restricted.requirement(marker) == "one of the roles A, B"
      assert_raise Protocol.UndefinedError, fn -> to_string(marker) end
    end
  end
end
