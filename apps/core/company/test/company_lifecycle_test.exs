defmodule Bilimbi.Core.CompanyLifecycleTest do
  @moduledoc """
  The lifecycle operations as a caller sees them: which transitions each
  verb makes, what a refused one returns, who may perform one, and the
  retained action each records beside the captured field change.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.Summary

  import Bilimbi.Core.Company.TestFixtures

  @user_id 91
  @company_id 73
  @capability "admin.company.update"

  setup do
    Code.ensure_loaded!(Bilimbi.Base.Authz.TestFixtures)
    Code.ensure_loaded!(Bilimbi.Base.Audit.TestFixtures)
    create_company_identity_tables!()
    Bilimbi.Base.Authz.TestFixtures.create_authz_tables!()
    Bilimbi.Base.Audit.TestFixtures.create_audit_tables!()
    install_company_authz!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    insert_tenant!()
    insert_tenant!(%{id: 42, name: "Other tenant", is_platform_operator: false})
    insert_company!(%{id: @company_id, name: "Bilimbi Industries"})

    {:ok, system_scope} = Tenancy.scope(41)
    scope = Authentication.sign_in(system_scope, @user_id, @company_id)

    %{scope: scope, system_scope: system_scope}
  end

  describe "transitions" do
    test "the table: every allowed pairing writes the status, every other one is refused", %{
      scope: scope
    } do
      grant!()

      table = [
        {"pending", :activate, "active"},
        {"pending", :archive, "archived"},
        {"active", :suspend, "suspended"},
        {"active", :archive, "archived"},
        {"suspended", :reactivate, "active"},
        {"suspended", :archive, "archived"}
      ]

      for {from, operation, to} <- table do
        set_status!(from)
        assert {:ok, %Summary{id: @company_id, status: ^to}} = call(operation, scope)
        assert stored_status() == to
      end

      refused =
        for from <- ~w(pending active suspended archived),
            operation <- [:activate, :reactivate, :suspend, :archive],
            {from, operation} not in Enum.map(table, fn {f, op, _to} -> {f, op} end),
            do: {from, operation}

      assert length(refused) == 10

      for {from, operation} <- refused do
        set_status!(from)
        assert {:error, {:invalid_transition, ^from}} = call(operation, scope)
        assert stored_status() == from
      end
    end

    test "archived is final: nothing leaves it and nothing is recorded", %{scope: scope} do
      grant!()
      set_status!("archived")

      for operation <- [:activate, :reactivate, :suspend, :archive] do
        assert {:error, {:invalid_transition, "archived"}} = call(operation, scope)
      end

      assert stored_status() == "archived"
      assert {:ok, []} = Audit.list_actions(scope)
      assert Company.lifecycle_operations("archived") == []
    end

    test "lifecycle_operations/1 offers exactly the table's rows in a fixed order" do
      assert Company.lifecycle_operations("pending") == [:activate, :archive]
      assert Company.lifecycle_operations("active") == [:suspend, :archive]
      assert Company.lifecycle_operations("suspended") == [:reactivate, :archive]
      assert Company.lifecycle_operations("archived") == []
    end
  end

  describe "audit" do
    test "each operation records one retained action naming the intent, the actor and the reason",
         %{scope: scope} do
      grant!()

      assert {:ok, _} = Company.suspend_company(scope, @company_id, reason: "  Unpaid invoices  ")
      assert {:ok, _} = Company.reactivate_company(scope, @company_id)
      assert {:ok, _} = Company.archive_company(scope, @company_id, reason: "Wound up")

      assert {:ok, actions} = Audit.list_actions(scope)

      assert Enum.map(actions, & &1.event) |> Enum.sort() ==
               ~w(company.archived company.reactivated company.suspended)

      suspended = Enum.find(actions, &(&1.event == "company.suspended"))
      assert suspended.actor_type == "user"
      assert suspended.actor_id == @user_id
      assert suspended.company_id == @company_id
      assert suspended.is_retained

      assert suspended.payload == %{
               "semantic" => true,
               "source" => "Company",
               "summary" => "Suspended company “Bilimbi Industries”",
               "subject" => %{
                 "name" => "company",
                 "id" => @company_id,
                 "label" => "Bilimbi Industries"
               },
               "context" => %{
                 "from_status" => "active",
                 "to_status" => "suspended",
                 "reason" => "Unpaid invoices"
               },
               "result" => "succeeded"
             }

      reactivated = Enum.find(actions, &(&1.event == "company.reactivated"))
      assert reactivated.payload["summary"] == "Reactivated company “Bilimbi Industries”"
      assert reactivated.payload["context"]["reason"] == nil

      archived = Enum.find(actions, &(&1.event == "company.archived"))

      assert archived.payload["context"] == %{
               "from_status" => "active",
               "to_status" => "archived",
               "reason" => "Wound up"
             }
    end

    test "a blank reason records none and an overlong one is refused before anything is written",
         %{scope: scope} do
      grant!()

      assert {:ok, _} = Company.suspend_company(scope, @company_id, reason: "   ")
      assert {:ok, [action]} = Audit.list_actions(scope)
      assert action.payload["context"]["reason"] == nil

      too_long = String.duplicate("x", Company.lifecycle_reason_max_length() + 1)

      assert {:error, :reason_too_long} =
               Company.reactivate_company(scope, @company_id, reason: too_long)

      assert stored_status() == "suspended"
      assert {:ok, [_only_the_suspension]} = Audit.list_actions(scope)
    end

    test "the operator behind an impersonated session and the request trace are recorded", %{
      system_scope: system_scope
    } do
      grant!()

      scope =
        Authentication.sign_in(system_scope, @user_id, @company_id,
          impersonator_id: 7,
          impersonation_session_id: "sess-7"
        )

      Bilimbi.Base.Audit.Context.put(%Bilimbi.Base.Audit.Context{
        actor_type: "user",
        actor_id: @user_id,
        impersonator_id: 7,
        trace_id: "trace-abc"
      })

      on_exit(fn -> Bilimbi.Base.Audit.Context.put(nil) end)

      assert {:ok, _} = Company.suspend_company(scope, @company_id)
      assert {:ok, [action]} = Audit.list_actions(scope)
      assert action.actor_id == @user_id
      assert action.impersonator_id == 7
      assert action.trace_id == "trace-abc"
    end
  end

  describe "authorization and identity" do
    test "without the update capability the operation is forbidden and nothing is written", %{
      scope: scope
    } do
      assert {:error, :forbidden} = Company.suspend_company(scope, @company_id)
      assert stored_status() == "active"
      assert {:ok, []} = Audit.list_actions(scope)
    end

    test "a system scope that names nobody is refused", %{system_scope: system_scope} do
      assert {:error, :forbidden} = Company.archive_company(system_scope, @company_id)
      assert stored_status() == "active"
    end

    test "a missing, soft-deleted or cross-tenant company is not found", %{scope: scope} do
      grant!()
      insert_company!(%{id: 74, code: "retired", deleted_at: ~N[2026-08-11 12:00:00]})
      insert_company!(%{id: 75, tenant_id: 42, code: "elsewhere"})

      assert {:error, :not_found} = Company.suspend_company(scope, 9999)
      assert {:error, :not_found} = Company.suspend_company(scope, 74)
      assert {:error, :not_found} = Company.suspend_company(scope, 75)
      assert {:error, :not_found} = Company.suspend_company(scope, "73")
      assert {:error, :not_found} = Company.suspend_company(scope, 0)
    end
  end

  describe "the generic paths" do
    test "update_company/3 refuses a status key instead of dropping it", %{system_scope: scope} do
      assert {:error, changeset} =
               Company.update_company(scope, @company_id, %{status: "archived"})

      assert {:status, {message, _}} = List.keyfind(changeset.errors, :status, 0)
      assert message =~ "lifecycle operation"

      assert {:error, changeset} =
               Company.update_company(scope, @company_id, %{
                 "status" => "suspended",
                 "name" => "X"
               })

      assert List.keyfind(changeset.errors, :status, 0)
      assert stored_status() == "active"
      assert Repo.get!(Bilimbi.Core.Company.Schema, @company_id).name == "Bilimbi Industries"
    end

    test "create_company/3 starts a company active or pending and nowhere else", %{
      system_scope: scope
    } do
      assert Company.initial_statuses() == ["active", "pending"]

      assert {:ok, %Summary{status: "active"}} =
               Company.create_company(scope, %{name: "Default Co"})

      assert {:ok, %Summary{status: "pending"}} =
               Company.create_company(scope, %{name: "Pending Co", status: "pending"})

      for status <- ~w(suspended archived) do
        assert {:error, changeset} =
                 Company.create_company(scope, %{name: "#{status} Co", status: status})

        assert {:status, _} = List.keyfind(changeset.errors, :status, 0)
      end
    end
  end

  defp call(:archive, scope), do: Company.archive_company(scope, @company_id)
  defp call(:suspend, scope), do: Company.suspend_company(scope, @company_id)
  defp call(:activate, scope), do: Company.activate_company(scope, @company_id)
  defp call(:reactivate, scope), do: Company.reactivate_company(scope, @company_id)

  defp set_status!(status) do
    Ecto.Adapters.SQL.query!(Repo, "UPDATE companies SET status = $1 WHERE id = $2", [
      status,
      @company_id
    ])
  end

  defp stored_status do
    Repo.get!(Bilimbi.Core.Company.Schema, @company_id).status
  end

  defp grant! do
    {:ok, scope} = Tenancy.scope(41)

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               scope,
               @company_id,
               :user,
               @user_id,
               @capability,
               true
             )
  end

  defp install_company_authz! do
    authz =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "core/company", otp_app: :bilimbi_core_company},
          payload: %{
            domains: %{"admin" => "Administrative operations"},
            verbs: ["update"],
            capabilities: [@capability],
            company_directory: Bilimbi.Core.Company.AuthzCompanyDirectory
          }
        }
      ])

    ContributionRegistry.put_consumers_for_test!(%{authz: authz}, "company-lifecycle")
  end
end
