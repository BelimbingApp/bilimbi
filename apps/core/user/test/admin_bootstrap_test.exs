defmodule Bilimbi.Core.User.AdminBootstrapTest do
  use Bilimbi.Base.Database.DataCase, async: false

  import Bilimbi.Core.User.TestFixtures

  alias Bilimbi.Base.Audit.TestFixtures, as: AuditFixtures
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User

  setup do
    create_user_tables!()
    create_bootstrap_receipt_table!()
    Bilimbi.Base.Authz.TestFixtures.create_authz_tables!()
    AuditFixtures.create_audit_tables!()
    install_user_authz_registry!()
    assert {:ok, _} = Authz.reconcile_system_roles()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  test "creates the selected admin, role assignment, receipt and retained console action" do
    assert {:ok, :created} = User.bootstrap_platform_admin(attributes())
    assert {:ok, user} = User.authenticate("operator@example.com", "bootstrap-password")
    assert {:ok, company} = Company.platform_operator_company()
    assert {:ok, scope} = Tenancy.scope(company.tenant_id)

    assert [%{role_code: "core_admin"}] =
             Authz.list_principal_role_assignments(scope, :user, user.id).entries

    assert {:ok, actions} = Bilimbi.Base.Audit.list_actions(scope)

    assert [%{actor_type: "console", actor_id: 0, is_retained: true}] =
             Enum.filter(actions, &(&1.event == "user.bootstrap.completed"))

    [[prefix]] =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT nspname FROM pg_namespace WHERE oid = pg_my_temp_schema()",
        []
      ).rows

    assert :ok =
             SchemaVerifier.verify(Repo, [User.SchemaContract.bootstrap_receipt()],
               prefix: prefix
             )

    assert [[%{"email" => "operator@example.com", "role" => "core_admin", "user_id" => id}]] =
             AuditFixtures.action_payloads("user.bootstrap.completed")

    assert id == user.id
    assert is_nil(user.email_verified_at)
  end

  test "repeats preserve passwords, later role revocation, and the one-time audit action" do
    assert {:ok, :created} = User.bootstrap_platform_admin(attributes())
    assert {:ok, user} = User.authenticate("operator@example.com", "bootstrap-password")

    assert {:ok, tenant_id} = Company.fetch_tenant_id_for_company(user.company_id)
    assert {:ok, scope} = Tenancy.scope(tenant_id)

    [assignment] = Authz.list_principal_role_assignments(scope, :user, user.id).entries
    assert {:ok, :unassigned} = Authz.unassign_role(scope, assignment.role_id, assignment.id)

    repeat = %{attributes() | password: "different-password", admin_name: "Changed"}
    assert {:ok, :already_completed} = User.bootstrap_platform_admin(repeat)
    assert {:ok, unchanged} = User.authenticate("operator@example.com", "bootstrap-password")
    assert unchanged.name == "Operator"
    assert [] == Authz.list_principal_role_assignments(scope, :user, user.id).entries
    assert length(AuditFixtures.action_payloads("user.bootstrap.completed")) == 1

    assert {:ok, :already_completed} =
             User.bootstrap_platform_admin(Map.delete(attributes(), :password))
  end

  test "a different identity cannot create a second administrator" do
    assert {:ok, :created} = User.bootstrap_platform_admin(attributes())

    assert {:error, :bootstrap_identity_conflict} =
             User.bootstrap_platform_admin(%{attributes() | admin_email: "second@example.com"})

    assert {:error, :invalid_credentials} =
             User.authenticate("second@example.com", "bootstrap-password")
  end

  test "any existing account, including one without a company, refuses initial bootstrap" do
    insert_user!(%{company_id: nil})
    assert {:error, :existing_users} = User.bootstrap_platform_admin(attributes())
    assert is_nil(Tenancy.platform_operator())
    assert AuditFixtures.action_payloads("user.bootstrap.completed") == []
  end

  test "an existing platform operator is not repurposed" do
    Bilimbi.Core.Company.TestFixtures.insert_tenant!(%{name: "Adopted operator"})
    assert {:error, :existing_platform_operator} = User.bootstrap_platform_admin(attributes())
  end

  test "failed validation rolls back the identity and can be retried" do
    assert {:error, :invalid_bootstrap_attributes} =
             User.bootstrap_platform_admin(%{attributes() | password: "x"})

    assert is_nil(Tenancy.platform_operator())
    assert {:ok, :created} = User.bootstrap_platform_admin(attributes())
  end

  test "missing roles roll back provisioning rather than leaving a login without authority" do
    Repo.delete_all("base_authz_roles")
    assert {:error, :system_roles_missing} = User.bootstrap_platform_admin(attributes())
    assert is_nil(Tenancy.platform_operator())
  end

  test "a database refusal of the retained audit action rolls back provisioning" do
    Ecto.Adapters.SQL.query!(
      Repo,
      """
      ALTER TABLE base_audit_actions ADD CONSTRAINT refuse_bootstrap_action
      CHECK (event <> 'user.bootstrap.completed')
      """,
      []
    )

    assert_raise Ecto.ConstraintError, fn ->
      User.bootstrap_platform_admin(attributes())
    end

    assert is_nil(Tenancy.platform_operator())

    assert {:error, :invalid_credentials} =
             User.authenticate("operator@example.com", "bootstrap-password")

    assert AuditFixtures.action_payloads("user.bootstrap.completed") == []
  end

  defp attributes do
    %{
      tenant_name: "Platform operator",
      company_name: "Operations",
      company_code: "operations",
      admin_name: "Operator",
      admin_email: "operator@example.com",
      password: "bootstrap-password"
    }
  end
end
