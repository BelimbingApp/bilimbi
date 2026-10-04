defmodule Bilimbi.Base.Authz.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.Authz.TestCompanyDirectory
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Identity
  alias Bilimbi.Base.Tenancy.Scope
  alias Ecto.Adapters.SQL

  def create_authz_tables! do
    statements = [
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_authz_roles (
        id bigserial PRIMARY KEY,
        company_id bigint,
        name varchar(255) NOT NULL,
        code varchar(255) NOT NULL,
        description text,
        is_system boolean NOT NULL DEFAULT false,
        grant_all boolean NOT NULL DEFAULT false,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT DROP
      """,
      """
      CREATE UNIQUE INDEX IF NOT EXISTS base_authz_roles_company_id_code_unique
        ON base_authz_roles (company_id, code)
      """,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_authz_role_capabilities (
        id bigserial PRIMARY KEY,
        role_id bigint NOT NULL REFERENCES base_authz_roles(id) ON DELETE CASCADE,
        capability_key varchar(255) NOT NULL,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT DROP
      """,
      """
      CREATE UNIQUE INDEX IF NOT EXISTS base_authz_role_capabilities_role_id_capability_key_unique
        ON base_authz_role_capabilities (role_id, capability_key)
      """,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_authz_principal_roles (
        id bigserial PRIMARY KEY,
        company_id bigint,
        principal_type varchar(40) NOT NULL,
        principal_id bigint NOT NULL,
        role_id bigint NOT NULL REFERENCES base_authz_roles(id) ON DELETE CASCADE,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT DROP
      """,
      """
      CREATE UNIQUE INDEX IF NOT EXISTS base_authz_principal_roles_unique
        ON base_authz_principal_roles (company_id, principal_type, principal_id, role_id)
      """,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_authz_principal_capabilities (
        id bigserial PRIMARY KEY,
        company_id bigint,
        principal_type varchar(40) NOT NULL,
        principal_id bigint NOT NULL,
        capability_key varchar(255) NOT NULL,
        is_allowed boolean NOT NULL DEFAULT true,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT DROP
      """,
      """
      CREATE UNIQUE INDEX IF NOT EXISTS base_authz_principal_caps_unique
        ON base_authz_principal_capabilities (
          company_id, principal_type, principal_id, capability_key
        )
      """,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_authz_system_principal_capabilities (
        id bigserial PRIMARY KEY,
        company_id bigint NOT NULL,
        principal varchar(100) NOT NULL,
        capability_key varchar(255) NOT NULL,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT DROP
      """,
      """
      CREATE UNIQUE INDEX IF NOT EXISTS base_authz_system_principal_caps_unique
        ON base_authz_system_principal_capabilities (company_id, principal, capability_key)
      """,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS base_authz_decision_logs (
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
      ) ON COMMIT DROP
      """
    ]

    Enum.each(statements, &SQL.query!(Repo, &1, []))
  end

  def install_test_registry! do
    authz =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{
            id: "base/authz",
            otp_app: :bilimbi_base_authz
          },
          payload: %{
            domains: %{"admin" => "Administrative operations"},
            verbs: ["view", "manage"],
            capabilities: ["admin.test.record.view", "admin.test.platform.manage"],
            platform_capabilities: ["admin.test.platform.manage"],
            roles: %{
              "all_access" => %{name: "All Access", grant_all: true},
              "viewer" => %{
                name: "Viewer",
                capabilities: ["admin.test.record.view"]
              }
            },
            company_directory: TestCompanyDirectory
          }
        }
      ])

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "authz-test",
      # Merged over the registry's own empty snapshot rather than written out
      # by hand: a consumer added later gets its correct empty shape here for
      # free, instead of this fixture raising KeyError on the new key (#496).
      consumers: Map.merge(ContributionRegistry.build!([]).consumers, %{authz: authz})
    })
  end

  @doc """
  Installs the principal-naming doubles on top of the current snapshot.

  Separate from `install_registry!/0` on purpose: most of this suite must keep
  running with **no** directory installed, which is the deployment where a
  principal keeps its durable id.
  """
  def install_principal_directory! do
    snapshot = ContributionRegistry.snapshot!()

    ContributionRegistry.put_snapshot_for_test!(
      put_in(snapshot.consumers.principal_directory, %{
        user: Bilimbi.Base.Authz.TestUserDirectory,
        agent: Bilimbi.Base.Authz.TestAgentDirectory
      })
    )
  end

  def scope(tenant_id \\ 1) do
    Scope.for_tenant(%Identity{
      id: tenant_id,
      name: "Tenant #{tenant_id}",
      status: "active",
      is_platform_operator: false
    })
  end

  def platform_scope do
    Scope.for_tenant(%Identity{
      id: 1,
      name: "Platform operator",
      status: "active",
      is_platform_operator: true
    })
  end

  # Raw SQL on purpose: the public API refuses `grant_all` on a custom role
  # (`Role` forces it false), so this is the only way a test can make one.
  def grant_role!(company_id, user_id, role_code, grant_all \\ false) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    %{rows: [[role_id]]} =
      SQL.query!(
        Repo,
        """
        INSERT INTO base_authz_roles (company_id, name, code, is_system, grant_all, created_at, updated_at)
        VALUES ($1, $2, $3, false, $4, $5, $6)
        ON CONFLICT (company_id, code) DO UPDATE SET grant_all = EXCLUDED.grant_all
        RETURNING id
        """,
        [company_id, role_code, role_code, grant_all, now, now]
      )

    SQL.query!(
      Repo,
      """
      INSERT INTO base_authz_principal_roles (company_id, principal_type, principal_id, role_id, created_at, updated_at)
      VALUES ($1, 'user', $2, $3, $4, $5)
      ON CONFLICT (company_id, principal_type, principal_id, role_id) DO NOTHING
      """,
      [company_id, user_id, role_id, now, now]
    )

    role_id
  end
end
