defmodule Bilimbi.Core.User.AdminAffiliationTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Password
  alias Bilimbi.Core.User.Summary
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias Ecto.Adapters.SQL

  setup do
    UserFixtures.create_user_tables!()
    UserFixtures.create_sessions_table!()
    Bilimbi.Base.Audit.TestFixtures.create_audit_tables!()
    Bilimbi.Base.Authz.TestFixtures.create_authz_tables!()
    UserFixtures.install_user_authz_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

    # Setup operator tenant (tenant_id = 1) with primary company 10 and secondary company 11
    CompanyFixtures.insert_tenant!(%{
      id: 1,
      name: "Operator Platform",
      is_platform_operator: true
    })

    CompanyFixtures.insert_company!(%{
      id: 10,
      tenant_id: 1,
      name: "Operator HQ",
      code: "OP-HQ"
    })

    CompanyFixtures.insert_company!(%{
      id: 11,
      tenant_id: 1,
      name: "Operator Branch",
      code: "OP-BR"
    })

    # Setup standard tenant (tenant_id = 2) with company 20 and company 21
    CompanyFixtures.insert_tenant!(%{
      id: 2,
      name: "Acme Corp",
      is_platform_operator: false
    })

    CompanyFixtures.insert_company!(%{
      id: 20,
      tenant_id: 2,
      name: "Acme Primary",
      code: "ACM-1"
    })

    CompanyFixtures.insert_company!(%{
      id: 21,
      tenant_id: 2,
      name: "Acme Secondary",
      code: "ACM-2"
    })

    op_scope = UserFixtures.operator_scope(1)
    tenant_scope = UserFixtures.tenant_scope(2)

    :ok = Bilimbi.Core.Employee.ensure_system_types()

    {:ok, emp_10} =
      Bilimbi.Core.Employee.create_employee(op_scope, 10, %{
        employee_number: "EMP-10-1",
        full_name: "Admin Operator",
        employee_type: "full_time"
      })

    {:ok, emp_20} =
      Bilimbi.Core.Employee.create_employee(tenant_scope, 20, %{
        employee_number: "EMP-20-1",
        full_name: "Alice Acme",
        employee_type: "full_time"
      })

    {:ok, emp_21} =
      Bilimbi.Core.Employee.create_employee(tenant_scope, 21, %{
        employee_number: "EMP-21-1",
        full_name: "Bob Acme",
        employee_type: "full_time"
      })

    UserFixtures.grant_role!(10, 1, "operator_admin", true)
    UserFixtures.grant_role!(20, 2, "user_admin", true)

    op_actor = Authz.actor(:user, 1, op_scope, 10)
    tenant_actor = Authz.actor(:user, 2, tenant_scope, 20)

    {:ok,
     op_scope: op_scope,
     tenant_scope: tenant_scope,
     op_actor: op_actor,
     tenant_actor: tenant_actor,
     emp_10: emp_10,
     emp_20: emp_20,
     emp_21: emp_21}
  end

  describe "unaffiliated user read and create (operator only)" do
    test "create_unaffiliated_user creates user with no company and records audit mutation",
         %{op_scope: op_scope, op_actor: op_actor} do
      assert {:ok, %Summary{} = user} =
               User.create_unaffiliated_user(op_actor, op_scope, %{
                 name: "Root Admin",
                 email: "root@example.com",
                 password: "supersecretpassword"
               })

      assert is_nil(user.company_id)
      assert is_nil(user.employee_id)
      assert user.email == "root@example.com"

      # Stored password must be Argon2id
      stored_hash = UserFixtures.stored_password(user.id)
      assert String.starts_with?(stored_hash, "$argon2id$")
      assert Password.valid?("supersecretpassword", stored_hash)

      # Audit mutation recorded
      audit_record = Repo.get_by(MutationSchema, auditable_id: to_string(user.id))
      assert audit_record
      assert audit_record.event == "created_unaffiliated"
      assert audit_record.new_values["email"] == "root@example.com"
      assert is_nil(audit_record.new_values["password"])
      assert is_nil(audit_record.new_values["password_hash"])
    end

    test "create_unaffiliated_user fails closed for non-operator tenant",
         %{tenant_scope: tenant_scope, tenant_actor: tenant_actor} do
      assert {:error, :not_platform_operator} =
               User.create_unaffiliated_user(tenant_actor, tenant_scope, %{
                 name: "Sneaky User",
                 email: "sneaky@example.com",
                 password: "password123"
               })
    end

    test "list_unaffiliated_users and get_unaffiliated_user isolation",
         %{op_scope: op_scope, op_actor: op_actor, tenant_scope: tenant_scope} do
      UserFixtures.insert_user!(%{
        id: 501,
        company_id: nil,
        employee_id: nil,
        email: "unaffil1@example.com",
        name: "Unaffiliated One"
      })

      UserFixtures.insert_user!(%{
        id: 502,
        company_id: 20,
        employee_id: nil,
        email: "affil20@example.com",
        name: "Affiliated 20"
      })

      assert {:ok, unaffiliated} = User.list_unaffiliated_users(op_actor, op_scope)
      unaffiliated_ids = Enum.map(unaffiliated, & &1.id)
      assert 501 in unaffiliated_ids
      refute 502 in unaffiliated_ids

      # Standard tenant list never returns unaffiliated users
      assert {:ok, company_users} = User.list_company_users(tenant_scope, 20)
      refute Enum.any?(company_users, &(&1.id == 501))

      # get_unaffiliated_user retrieves unaffiliated user
      assert {:ok, %Summary{id: 501}} = User.get_unaffiliated_user(op_actor, op_scope, 501)

      # get_unaffiliated_user fails closed on affiliated user
      assert {:error, :user_not_found} = User.get_unaffiliated_user(op_actor, op_scope, 502)
    end
  end

  describe "assign_unaffiliated_user/5" do
    test "assigns unaffiliated user to company, sets employee, terminates sessions and audits",
         %{op_scope: op_scope, op_actor: op_actor, emp_10: emp_10} do
      UserFixtures.insert_user!(%{
        id: 601,
        company_id: nil,
        employee_id: nil,
        email: "pending@example.com"
      })

      # Seed an active session for the user
      SQL.query!(
        Repo,
        """
        INSERT INTO sessions (id, user_id, payload, last_activity)
        VALUES ('sess-601-a', 601, 'dummy-payload', 1234567890)
        """,
        []
      )

      assert {:ok, %Summary{} = updated} =
               User.assign_unaffiliated_user(op_actor, op_scope, 601, 10,
                 employee_id: emp_10.id,
                 current_session_id: "my-current-session"
               )

      assert updated.company_id == 10
      assert updated.employee_id == emp_10.id

      # Session must be terminated
      assert Repo.all(from s in "sessions", where: s.user_id == 601, select: s.id) == []

      # Audit mutation recorded
      audit_record = Repo.get_by(MutationSchema, auditable_id: "601", event: "assigned_company")
      assert audit_record
      assert audit_record.company_id == 10
      assert audit_record.new_values["company_id"] == 10
      assert audit_record.new_values["employee_id"] == emp_10.id
    end

    test "fails if employee does not belong to target company",
         %{op_scope: op_scope, op_actor: op_actor, emp_20: emp_20} do
      UserFixtures.insert_user!(%{
        id: 602,
        company_id: nil,
        employee_id: nil,
        email: "pending2@example.com"
      })

      # Employee emp_20 belongs to company 20, not company 10
      assert {:error, :employee_not_found} =
               User.assign_unaffiliated_user(op_actor, op_scope, 602, 10, employee_id: emp_20.id)

      # User remains unaffiliated
      assert {:ok, %Summary{company_id: nil}} =
               User.get_unaffiliated_user(op_actor, op_scope, 602)
    end
  end

  describe "reassign_user_company/6" do
    test "reassigns company, resets or updates employee, terminates sessions and audits",
         %{tenant_scope: tenant_scope, tenant_actor: tenant_actor, emp_20: emp_20} do
      UserFixtures.insert_user!(%{
        id: 701,
        company_id: 20,
        employee_id: emp_20.id,
        email: "mover@example.com"
      })

      SQL.query!(
        Repo,
        """
        INSERT INTO sessions (id, user_id, payload, last_activity)
        VALUES ('sess-701-a', 701, 'dummy-payload', 1234567890)
        """,
        []
      )

      # Reassigning from company 20 to 21 without employee_id clears previous employee link
      assert {:ok, %Summary{} = updated} =
               User.reassign_user_company(tenant_actor, tenant_scope, 20, 701, 21)

      assert updated.company_id == 21
      assert is_nil(updated.employee_id)

      # Old session terminated
      assert Repo.all(from s in "sessions", where: s.user_id == 701, select: s.id) == []

      # Audit mutation recorded
      audit_record =
        Repo.get_by(MutationSchema, auditable_id: "701", event: "reassigned_company")

      assert audit_record
      assert audit_record.old_values["company_id"] == 20
      assert audit_record.new_values["company_id"] == 21
      assert audit_record.old_values["employee_id"] == emp_20.id
      assert is_nil(audit_record.new_values["employee_id"])
    end

    test "reassigns company with valid employee for target company",
         %{tenant_scope: tenant_scope, tenant_actor: tenant_actor, emp_20: emp_20, emp_21: emp_21} do
      UserFixtures.insert_user!(%{
        id: 702,
        company_id: 20,
        employee_id: emp_20.id,
        email: "mover2@example.com"
      })

      assert {:ok, %Summary{} = updated} =
               User.reassign_user_company(tenant_actor, tenant_scope, 20, 702, 21,
                 employee_id: emp_21.id
               )

      assert updated.company_id == 21
      assert updated.employee_id == emp_21.id
    end

    test "fails and rolls back if new employee belongs to wrong company",
         %{tenant_scope: tenant_scope, tenant_actor: tenant_actor, emp_20: emp_20} do
      UserFixtures.insert_user!(%{
        id: 703,
        company_id: 20,
        employee_id: emp_20.id,
        email: "mover3@example.com"
      })

      # Employee emp_20 belongs to company 20, not target company 21
      assert {:error, :employee_not_found} =
               User.reassign_user_company(tenant_actor, tenant_scope, 20, 703, 21,
                 employee_id: emp_20.id
               )

      # User remains on company 20 with employee emp_20.id
      assert {:ok, %Summary{company_id: 20, employee_id: emp_id}} =
               User.get_user(tenant_scope, 20, 703)

      assert emp_id == emp_20.id
    end
  end

  describe "clear_user_company/5" do
    test "clears company and employee affiliation, makes user unaffiliated",
         %{
           tenant_scope: tenant_scope,
           tenant_actor: tenant_actor,
           op_scope: op_scope,
           op_actor: op_actor,
           emp_20: emp_20
         } do
      UserFixtures.insert_user!(%{
        id: 801,
        company_id: 20,
        employee_id: emp_20.id,
        email: "to_clear@example.com"
      })

      assert {:ok, %Summary{} = updated} =
               User.clear_user_company(tenant_actor, tenant_scope, 20, 801)

      assert is_nil(updated.company_id)
      assert is_nil(updated.employee_id)

      # User is now invisible to company 20
      assert {:error, :user_not_found} = User.get_user(tenant_scope, 20, 801)

      # User is now visible to operator unaffiliated query
      assert {:ok, %Summary{id: 801}} = User.get_unaffiliated_user(op_actor, op_scope, 801)

      # Audit mutation recorded
      audit_record = Repo.get_by(MutationSchema, auditable_id: "801", event: "cleared_company")
      assert audit_record
      assert audit_record.old_values["company_id"] == 20
      assert is_nil(audit_record.new_values["company_id"])
    end
  end

  describe "admin_change_password/6" do
    test "admin resets affiliated user password, updates hash to Argon2id, rotates token, terminates sessions",
         %{tenant_scope: tenant_scope, tenant_actor: tenant_actor} do
      UserFixtures.insert_user!(%{
        id: 901,
        company_id: 20,
        email: "pw_target@example.com",
        password_hash: UserFixtures.legacy_password_hash("oldpassword"),
        remember_token: "old-token"
      })

      SQL.query!(
        Repo,
        """
        INSERT INTO sessions (id, user_id, payload, last_activity)
        VALUES ('sess-901-a', 901, 'dummy-payload', 1234567890)
        """,
        []
      )

      assert {:ok, %Summary{id: 901}} =
               User.admin_change_password(
                 tenant_actor,
                 tenant_scope,
                 20,
                 901,
                 "brandnewsecurepassword123"
               )

      # New hash is Argon2id and authenticates with new password
      stored_hash = UserFixtures.stored_password(901)
      assert String.starts_with?(stored_hash, "$argon2id$")
      assert Password.valid?("brandnewsecurepassword123", stored_hash)
      refute Password.valid?("oldpassword", stored_hash)

      # Remember token is rotated
      stored_token = UserFixtures.stored_remember_token(901)
      assert is_binary(stored_token)
      refute stored_token == "old-token"

      # Sessions terminated
      assert Repo.all(from s in "sessions", where: s.user_id == 901, select: s.id) == []

      # Audit mutation recorded without credentials
      audit_record =
        Repo.get_by(MutationSchema, auditable_id: "901", event: "password_reset")

      assert audit_record
      assert audit_record.new_values["password_changed"] == true
      assert is_nil(audit_record.new_values["password"])
      assert is_nil(audit_record.new_values["password_hash"])
    end

    test "operator resets unaffiliated user password (company_id: nil)",
         %{op_scope: op_scope, op_actor: op_actor} do
      UserFixtures.insert_user!(%{
        id: 902,
        company_id: nil,
        employee_id: nil,
        email: "unaffil_pw@example.com",
        password_hash: UserFixtures.password_hash("oldunaffil")
      })

      assert {:ok, %Summary{id: 902}} =
               User.admin_change_password(
                 op_actor,
                 op_scope,
                 nil,
                 902,
                 "freshoperatorpassword123"
               )

      stored_hash = UserFixtures.stored_password(902)
      assert Password.valid?("freshoperatorpassword123", stored_hash)
    end

    test "rejects short password (< 8 chars)",
         %{tenant_scope: tenant_scope, tenant_actor: tenant_actor} do
      UserFixtures.insert_user!(%{
        id: 903,
        company_id: 20,
        email: "short_pw@example.com"
      })

      assert {:error, %Ecto.Changeset{errors: errors}} =
               User.admin_change_password(
                 tenant_actor,
                 tenant_scope,
                 20,
                 903,
                 "short"
               )

      assert errors[:password]
    end
  end
end
