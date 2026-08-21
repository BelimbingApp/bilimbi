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

      # The explicit semantic mutation is recorded. Repo-level capture (ADR
      # 0013) records additional "listener" rows for the same write, so the
      # lookup names the semantic event rather than assuming one row.
      audit_record =
        Repo.get_by(MutationSchema,
          auditable_id: to_string(user.id),
          event: "created_unaffiliated"
        )

      assert audit_record
      assert audit_record.new_values["email"] == "root@example.com"
      assert is_nil(audit_record.new_values["password"])
      assert is_nil(audit_record.new_values["password_hash"])

      # And the listener row for the user insert never stored the secret.
      listener_record =
        Repo.get_by(MutationSchema,
          auditable_id: to_string(user.id),
          source: "listener",
          auditable_type: "Bilimbi.Core.User.Schema"
        )

      assert listener_record
      assert listener_record.new_values["password_hash"] in [nil, "[redacted]"]
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

  describe "malformed lifecycle identifiers" do
    test "assign_unaffiliated_user fails closed before querying malformed user and company ids",
         %{
           op_scope: op_scope,
           op_actor: op_actor
         } do
      assert {:error, :user_not_found} =
               User.assign_unaffiliated_user(op_actor, op_scope, "not-a-user", 10)

      assert {:error, :company_not_found} =
               User.assign_unaffiliated_user(op_actor, op_scope, 601, "not-a-company")
    end

    test "reassign_user_company fails closed for malformed current, user, and target ids", %{
      tenant_scope: tenant_scope,
      tenant_actor: tenant_actor
    } do
      assert {:error, :company_not_found} =
               User.reassign_user_company(tenant_actor, tenant_scope, "not-a-company", 701, 21)

      assert {:error, :user_not_found} =
               User.reassign_user_company(tenant_actor, tenant_scope, 20, "not-a-user", 21)

      assert {:error, :company_not_found} =
               User.reassign_user_company(tenant_actor, tenant_scope, 20, 701, "not-a-company")
    end

    test "clear_user_company fails closed before querying malformed company and user ids", %{
      tenant_scope: tenant_scope,
      tenant_actor: tenant_actor
    } do
      assert {:error, :company_not_found} =
               User.clear_user_company(tenant_actor, tenant_scope, "not-a-company", 801)

      assert {:error, :user_not_found} =
               User.clear_user_company(tenant_actor, tenant_scope, 20, "not-a-user")
    end

    test "admin_change_password fails closed before querying malformed company and user ids", %{
      tenant_scope: tenant_scope,
      tenant_actor: tenant_actor
    } do
      assert {:error, :company_not_found} =
               User.admin_change_password(
                 tenant_actor,
                 tenant_scope,
                 "not-a-company",
                 901,
                 "brandnewsecurepassword123"
               )

      assert {:error, :user_not_found} =
               User.admin_change_password(
                 tenant_actor,
                 tenant_scope,
                 20,
                 "not-a-user",
                 "brandnewsecurepassword123"
               )
    end
  end

  describe "lifecycle rejection and atomicity" do
    test "assign_unaffiliated_user rejects a cross-tenant target company", %{
      op_scope: op_scope,
      op_actor: op_actor
    } do
      UserFixtures.insert_user!(%{
        id: 910,
        company_id: nil,
        employee_id: nil,
        email: "cross-tenant-target@example.com"
      })

      assert {:error, :company_not_found} =
               User.assign_unaffiliated_user(op_actor, op_scope, 910, 20)

      assert {:ok, %Summary{id: 910, company_id: nil, employee_id: nil}} =
               User.get_unaffiliated_user(op_actor, op_scope, 910)

      refute Repo.get_by(MutationSchema, auditable_id: "910", event: "assigned_company")
    end

    test "assign_unaffiliated_user rejects a soft-deleted target company", %{
      op_scope: op_scope,
      op_actor: op_actor
    } do
      UserFixtures.insert_user!(%{
        id: 911,
        company_id: nil,
        employee_id: nil,
        email: "deleted-target@example.com"
      })

      SQL.query!(Repo, "UPDATE companies SET deleted_at = $1 WHERE id = $2", [
        ~N[2026-08-17 00:00:00],
        11
      ])

      assert {:error, :company_not_found} =
               User.assign_unaffiliated_user(op_actor, op_scope, 911, 11)

      assert {:ok, %Summary{id: 911, company_id: nil, employee_id: nil}} =
               User.get_unaffiliated_user(op_actor, op_scope, 911)

      refute Repo.get_by(MutationSchema, auditable_id: "911", event: "assigned_company")
    end

    test "a post-update session failure rolls back password, sessions, and audit", %{
      tenant_scope: tenant_scope,
      tenant_actor: tenant_actor
    } do
      old_hash = UserFixtures.legacy_password_hash("oldpassword")

      UserFixtures.insert_user!(%{
        id: 912,
        company_id: 20,
        email: "rollback-tail@example.com",
        password_hash: old_hash,
        remember_token: "unchanged-token"
      })

      SQL.query!(
        Repo,
        "INSERT INTO sessions (id, user_id, payload, last_activity) VALUES ($1, $2, $3, $4)",
        ["rollback-tail-session", 912, "opaque", 1]
      )

      # The public Session guard is called after `apply_password_reset/2` inside
      # Core User's transaction, so this failure exercises the transaction tail.
      assert_raise FunctionClauseError, fn ->
        User.admin_change_password(
          tenant_actor,
          tenant_scope,
          20,
          912,
          "brandnewsecurepassword123",
          current_session_id: ""
        )
      end

      assert {:ok, %Summary{company_id: 20}} = User.get_user(tenant_scope, 20, 912)
      assert UserFixtures.stored_password(912) == old_hash
      assert UserFixtures.stored_remember_token(912) == "unchanged-token"

      assert Repo.all(from(s in "sessions", where: s.user_id == 912, select: s.id)) == [
               "rollback-tail-session"
             ]

      refute Repo.get_by(MutationSchema, auditable_id: "912", event: "password_reset")
    end
  end
end

defmodule Bilimbi.Core.User.AdminAffiliationConcurrencyTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.Summary
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    schema = unique_schema!()
    create_concurrency_schema!(schema)
    UserFixtures.install_user_authz_registry!()

    on_exit(fn ->
      ContributionRegistry.clear_for_test!()
      drop_concurrency_schema!(schema)
    end)

    on_schema!(schema, fn ->
      seed_concurrency_data!()
    end)

    scope = UserFixtures.tenant_scope(2)
    actor = Authz.actor(:user, 2, scope, 20)

    %{schema: schema, scope: scope, actor: actor}
  end

  test "a waiting lifecycle mutation rereads the user after a concurrent reassign", %{
    schema: schema,
    scope: scope,
    actor: actor
  } do
    parent = self()

    blocker =
      Task.async(fn ->
        checkout_and_on_schema!(schema, fn ->
          Repo.transaction(fn ->
            %{rows: [[950]]} =
              SQL.query!(Repo, "SELECT id FROM users WHERE id = 950 FOR UPDATE", [])

            send(parent, :user_row_locked)
            await_message!(:release_user_row)
          end)
        end)
      end)

    assert_receive :user_row_locked, 5_000

    winner =
      Task.async(fn ->
        checkout_and_on_schema!(schema, fn ->
          send(parent, {:winner_backend, backend_pid!()})

          User.reassign_user_company(actor, scope, 20, 950, 21,
            current_session_id: "keep-race-session"
          )
        end)
      end)

    assert_receive {:winner_backend, winner_backend}, 5_000
    await_backend_lock_wait!(winner_backend)

    loser =
      Task.async(fn ->
        checkout_and_on_schema!(schema, fn ->
          send(parent, {:loser_backend, backend_pid!()})

          User.clear_user_company(actor, scope, 20, 950,
            current_session_id: "loser-current-session"
          )
        end)
      end)

    assert_receive {:loser_backend, loser_backend}, 5_000
    await_backend_lock_wait!(loser_backend)

    try do
      send(blocker.pid, :release_user_row)

      assert {:ok, :ok} = Task.await(blocker, 5_000)

      assert {:ok, %Summary{id: 950, company_id: 21, employee_id: nil}} =
               Task.await(winner, 5_000)

      assert {:error, :user_not_found} = Task.await(loser, 5_000)

      on_schema!(schema, fn ->
        assert %{rows: [[21, nil]]} =
                 SQL.query!(Repo, "SELECT company_id, employee_id FROM users WHERE id = 950", [])

        assert %{rows: [["keep-race-session"]]} =
                 SQL.query!(Repo, "SELECT id FROM sessions WHERE user_id = 950", [])

        assert %{rows: [[1]]} =
                 SQL.query!(
                   Repo,
                   "SELECT count(*) FROM base_audit_mutations WHERE auditable_id = '950' AND event = 'reassigned_company'",
                   []
                 )

        assert %{rows: [[0]]} =
                 SQL.query!(
                   Repo,
                   "SELECT count(*) FROM base_audit_mutations WHERE auditable_id = '950' AND event = 'cleared_company'",
                   []
                 )
      end)
    after
      send(blocker.pid, :release_user_row)
      Enum.each([blocker, winner, loser], &Task.shutdown(&1, :brutal_kill))
    end
  end

  defp unique_schema! do
    random_suffix = :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
    "user_affiliation_race_#{random_suffix}"
  end

  defp create_concurrency_schema!(schema) do
    quoted_schema = quote_ident!(schema)
    SQL.query!(Repo, "CREATE SCHEMA #{quoted_schema}", [])

    statements = [
      """
      CREATE TABLE #{quoted_schema}.companies (
        id bigserial PRIMARY KEY,
        parent_id bigint,
        tenant_id bigint NOT NULL,
        name varchar(255) NOT NULL,
        code varchar(255) NOT NULL UNIQUE,
        status varchar(255) NOT NULL DEFAULT 'active',
        legal_name varchar(255),
        registration_number varchar(255),
        tax_id varchar(255),
        legal_entity_type_id bigint,
        jurisdiction varchar(255),
        email varchar(255),
        website varchar(255),
        scope_activities json,
        metadata json,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        deleted_at timestamp(0) without time zone
      )
      """,
      """
      CREATE TABLE #{quoted_schema}.users (
        id bigserial PRIMARY KEY,
        company_id bigint,
        employee_id bigint,
        name varchar(255) NOT NULL,
        email varchar(255) NOT NULL,
        email_verified_at timestamp(0) without time zone,
        password varchar(255) NOT NULL,
        remember_token varchar(100),
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      )
      """,
      """
      CREATE TABLE #{quoted_schema}.sessions (
        id varchar(255) PRIMARY KEY,
        user_id bigint,
        ip_address varchar(45),
        user_agent text,
        payload text NOT NULL,
        last_activity integer NOT NULL
      )
      """,
      """
      CREATE TABLE #{quoted_schema}.base_audit_mutations (
        id bigserial PRIMARY KEY,
        company_id bigint,
        tenant_id bigint,
        actor_type varchar(40) NOT NULL,
        actor_id bigint NOT NULL,
        actor_role varchar(100),
        ip_address inet,
        url text,
        user_agent varchar(80),
        auditable_type varchar(255) NOT NULL,
        auditable_id varchar(128) NOT NULL,
        subject_name varchar(255),
        subject_id varchar(128),
        subject_identifier varchar(255),
        source varchar(20) NOT NULL DEFAULT 'listener',
        event varchar(20) NOT NULL,
        old_values jsonb,
        new_values jsonb,
        trace_id varchar(12),
        occurred_at timestamp(0) without time zone NOT NULL
      )
      """,
      """
      CREATE TABLE #{quoted_schema}.base_authz_roles (
        id bigserial PRIMARY KEY,
        company_id bigint,
        is_system boolean NOT NULL DEFAULT false,
        grant_all boolean NOT NULL DEFAULT false
      )
      """,
      """
      CREATE TABLE #{quoted_schema}.base_authz_principal_roles (
        id bigserial PRIMARY KEY,
        company_id bigint,
        principal_type varchar(40) NOT NULL,
        principal_id bigint NOT NULL,
        role_id bigint NOT NULL
      )
      """,
      """
      CREATE TABLE #{quoted_schema}.base_authz_principal_capabilities (
        id bigserial PRIMARY KEY,
        company_id bigint,
        principal_type varchar(40) NOT NULL,
        principal_id bigint NOT NULL,
        capability_key varchar(255) NOT NULL,
        is_allowed boolean NOT NULL DEFAULT true
      )
      """,
      """
      CREATE TABLE #{quoted_schema}.base_authz_decision_logs (
        id bigserial PRIMARY KEY,
        company_id bigint,
        actor_type varchar(40) NOT NULL,
        actor_id bigint NOT NULL,
        acting_for_user_id bigint,
        capability varchar(255) NOT NULL,
        resource_type varchar(255),
        resource_id varchar(255),
        allowed boolean NOT NULL,
        reason_code varchar(255) NOT NULL,
        applied_policies json,
        context json,
        trace_id varchar(12),
        occurred_at timestamp(0) without time zone NOT NULL,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      )
      """
    ]

    Enum.each(statements, &SQL.query!(Repo, &1, []))
  end

  defp seed_concurrency_data! do
    SQL.query!(
      Repo,
      """
      INSERT INTO companies (id, tenant_id, name, code, status, deleted_at)
      VALUES (20, 2, 'Current', 'current', 'active', NULL),
             (21, 2, 'Target', 'target', 'active', NULL)
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO users (id, company_id, employee_id, name, email, password)
      VALUES (950, 20, NULL, 'Race Target', 'race-target@example.com', $1)
      """,
      [UserFixtures.password_hash("race-password")]
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO sessions (id, user_id, payload, last_activity)
      VALUES ('keep-race-session', 950, 'opaque', 1)
      """,
      []
    )

    %{rows: [[role_id]]} =
      SQL.query!(
        Repo,
        """
        INSERT INTO base_authz_roles (company_id, is_system, grant_all)
        VALUES (20, false, true)
        RETURNING id
        """,
        []
      )

    SQL.query!(
      Repo,
      """
      INSERT INTO base_authz_principal_roles (company_id, principal_type, principal_id, role_id)
      VALUES (20, 'user', 2, $1)
      """,
      [role_id]
    )
  end

  defp backend_pid! do
    %{rows: [[backend_pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
    backend_pid
  end

  defp await_message!(message) do
    receive do
      ^message -> :ok
    after
      5_000 -> Repo.rollback({:timeout, message})
    end
  end

  defp await_backend_lock_wait!(backend_pid), do: await_backend_lock_wait!(backend_pid, 50)

  defp await_backend_lock_wait!(_backend_pid, 0) do
    flunk("contender never waited on a PostgreSQL row lock")
  end

  defp await_backend_lock_wait!(backend_pid, remaining) do
    %{rows: rows} =
      SQL.query!(Repo, "SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [
        backend_pid
      ])

    case rows do
      [["Lock"]] ->
        :ok

      _other ->
        receive do
        after
          20 -> await_backend_lock_wait!(backend_pid, remaining - 1)
        end
    end
  end

  defp checkout_and_on_schema!(schema, fun) do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    on_schema!(schema, fun)
  end

  defp on_schema!(schema, fun) do
    SQL.query!(Repo, "SET search_path TO #{quote_ident!(schema)}", [])

    try do
      fun.()
    after
      SQL.query!(Repo, "SET search_path TO public", [])
    end
  end

  defp drop_concurrency_schema!(schema) do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    SQL.query!(Repo, "DROP SCHEMA IF EXISTS #{quote_ident!(schema)} CASCADE", [])
  end

  defp quote_ident!(identifier) when is_binary(identifier) do
    if identifier =~ ~r/^[a-z][a-z0-9_]*$/ do
      ~s("#{identifier}")
    else
      raise ArgumentError, "refusing unsafe schema identifier #{inspect(identifier)}"
    end
  end
end
