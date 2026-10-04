defmodule Bilimbi.Core.User.AdminAffiliationTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Authentication
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
    AuthzFixtures.create_authz_tables!()
    UserFixtures.install_user_authz_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)

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

    tenant_scope = UserFixtures.tenant_scope(2)

    :ok = Bilimbi.Core.Employee.ensure_system_types()

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

    AuthzFixtures.grant_role!(20, 2, "user_admin", true)

    # The administrator holds the grant in company 20 and is signed in at 21.
    admin = Authentication.sign_in(tenant_scope, 2, 21)

    {:ok, tenant_scope: tenant_scope, admin: admin, emp_20: emp_20, emp_21: emp_21}
  end

  describe "reassign_user_company/5" do
    test "reassigns company, resets or updates employee, terminates sessions and audits",
         %{admin: admin, emp_20: emp_20} do
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
               User.reassign_user_company(admin, 20, 701, 21)

      assert updated.company_id == 21
      assert is_nil(updated.employee_id)

      # Old session terminated
      assert Repo.all(from(s in "sessions", where: s.user_id == 701, select: s.id)) == []

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
         %{admin: admin, emp_20: emp_20, emp_21: emp_21} do
      UserFixtures.insert_user!(%{
        id: 702,
        company_id: 20,
        employee_id: emp_20.id,
        email: "mover2@example.com"
      })

      assert {:ok, %Summary{} = updated} =
               User.reassign_user_company(admin, 20, 702, 21, employee_id: emp_21.id)

      assert updated.company_id == 21
      assert updated.employee_id == emp_21.id
    end

    test "fails and rolls back if new employee belongs to wrong company",
         %{tenant_scope: tenant_scope, admin: admin, emp_20: emp_20} do
      UserFixtures.insert_user!(%{
        id: 703,
        company_id: 20,
        employee_id: emp_20.id,
        email: "mover3@example.com"
      })

      # Employee emp_20 belongs to company 20, not target company 21
      assert {:error, :employee_not_found} =
               User.reassign_user_company(admin, 20, 703, 21, employee_id: emp_20.id)

      # User remains on company 20 with employee emp_20.id
      assert {:ok, %Summary{company_id: 20, employee_id: emp_id}} =
               User.get_user(tenant_scope, 20, 703)

      assert emp_id == emp_20.id
    end
  end

  describe "admin_change_password/5" do
    test "admin resets affiliated user password, updates hash to Argon2id, rotates token, terminates sessions",
         %{admin: admin} do
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
                 admin,
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
      assert Repo.all(from(s in "sessions", where: s.user_id == 901, select: s.id)) == []

      # Audit mutation recorded without credentials
      audit_record =
        Repo.get_by(MutationSchema, auditable_id: "901", event: "password_reset")

      assert audit_record
      assert audit_record.new_values["password_changed"] == true
      assert is_nil(audit_record.new_values["password"])
      assert is_nil(audit_record.new_values["password_hash"])
    end

    test "rejects short password (< 8 chars)",
         %{admin: admin} do
      UserFixtures.insert_user!(%{
        id: 903,
        company_id: 20,
        email: "short_pw@example.com"
      })

      assert {:error, %Ecto.Changeset{errors: errors}} =
               User.admin_change_password(
                 admin,
                 20,
                 903,
                 "short"
               )

      assert errors[:password]
    end
  end

  describe "malformed lifecycle identifiers" do
    test "reassign_user_company fails closed for malformed current, user, and target ids", %{
      admin: admin
    } do
      assert {:error, :company_not_found} =
               User.reassign_user_company(admin, "not-a-company", 701, 21)

      assert {:error, :user_not_found} =
               User.reassign_user_company(admin, 20, "not-a-user", 21)

      assert {:error, :company_not_found} =
               User.reassign_user_company(admin, 20, 701, "not-a-company")
    end

    test "admin_change_password fails closed before querying malformed company and user ids", %{
      admin: admin
    } do
      assert {:error, :company_not_found} =
               User.admin_change_password(
                 admin,
                 "not-a-company",
                 901,
                 "brandnewsecurepassword123"
               )

      assert {:error, :user_not_found} =
               User.admin_change_password(
                 admin,
                 20,
                 "not-a-user",
                 "brandnewsecurepassword123"
               )
    end
  end

  describe "the grant is judged in the account's company" do
    setup do
      UserFixtures.insert_user!(%{id: 801, company_id: 20, email: "subject@example.com"})
      :ok
    end

    test "the audit row names the signed-in administrator", %{admin: admin} do
      assert {:ok, %Summary{id: 801}} =
               User.admin_change_password(admin, 20, 801, "brandnewsecurepassword123")

      assert %{actor_type: "user", actor_id: 2, company_id: 20} =
               Repo.get_by(MutationSchema, auditable_id: "801", event: "password_reset")
    end

    test "a grant only in the company signed in at does not reach the account's company", %{
      tenant_scope: tenant_scope
    } do
      AuthzFixtures.grant_role!(21, 3, "user_admin_21", true)
      elsewhere = Authentication.sign_in(tenant_scope, 3, 21)
      before = UserFixtures.stored_password(801)

      assert {:error, :unauthorized} =
               User.admin_change_password(elsewhere, 20, 801, "brandnewsecurepassword123")

      assert {:error, :unauthorized} = User.reassign_user_company(elsewhere, 20, 801, 21)
      assert UserFixtures.stored_password(801) == before
    end

    test "an archived company's grant allows nothing", %{tenant_scope: tenant_scope} do
      CompanyFixtures.insert_company!(%{
        id: 22,
        tenant_id: 2,
        name: "Acme Archived",
        code: "ACM-3",
        deleted_at: ~N[2026-01-01 00:00:00]
      })

      UserFixtures.insert_user!(%{id: 802, company_id: 22, email: "archived@example.com"})
      AuthzFixtures.grant_role!(22, 2, "user_admin_22", true)
      admin = Authentication.sign_in(tenant_scope, 2, 21)

      assert {:error, :unauthorized} =
               User.admin_change_password(admin, 22, 802, "brandnewsecurepassword123")

      assert {:error, :unauthorized} = User.reassign_user_company(admin, 22, 802, 21)
    end

    test "an administrator of another tenant is refused whatever they hold" do
      CompanyFixtures.insert_tenant!(%{id: 3, name: "Other", is_platform_operator: false})

      CompanyFixtures.insert_company!(%{
        id: 30,
        tenant_id: 3,
        name: "Other Primary",
        code: "OTH-1"
      })

      AuthzFixtures.grant_role!(30, 9, "user_admin_30", true)
      AuthzFixtures.grant_role!(20, 9, "user_admin_stray", true)
      outsider = Authentication.sign_in(UserFixtures.tenant_scope(3), 9, 30)

      assert {:error, :unauthorized} =
               User.admin_change_password(outsider, 20, 801, "brandnewsecurepassword123")

      assert {:error, :unauthorized} = User.reassign_user_company(outsider, 20, 801, 21)
    end

    test "a system scope names nobody and is refused", %{tenant_scope: tenant_scope} do
      assert {:error, :unauthorized} =
               User.admin_change_password(tenant_scope, 20, 801, "brandnewsecurepassword123")

      assert {:error, :unauthorized} = User.reassign_user_company(tenant_scope, 20, 801, 21)
    end
  end

  describe "lifecycle rejection and atomicity" do
    test "a post-update session failure rolls back password, sessions, and audit", %{
      tenant_scope: tenant_scope,
      admin: admin
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
          admin,
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

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Authentication
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
    %{schema: schema, scope: Authentication.sign_in(scope, 2, 20)}
  end

  test "a waiting lifecycle mutation rereads the user after a concurrent reassign", %{
    schema: schema,
    scope: scope
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

          User.reassign_user_company(scope, 20, 950, 21, current_session_id: "keep-race-session")
        end)
      end)

    assert_receive {:winner_backend, winner_backend}, 5_000
    await_backend_lock_wait!(winner_backend)

    loser =
      Task.async(fn ->
        checkout_and_on_schema!(schema, fn ->
          send(parent, {:loser_backend, backend_pid!()})

          User.reassign_user_company(scope, 20, 950, 21,
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
