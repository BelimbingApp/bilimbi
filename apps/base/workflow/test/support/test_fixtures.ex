Code.require_file(Path.expand("../../../database/test/support/data_case.ex", __DIR__))
Code.require_file(Path.expand("../../../tenancy/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../../audit/test/support/test_fixtures.ex", __DIR__))
Code.require_file(Path.expand("../../../authz/test/support/test_fixtures.ex", __DIR__))

defmodule Bilimbi.Base.Workflow.TestFixtures do
  @moduledoc false
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo

  alias Bilimbi.Base.Workflow.{
    ContributionValidator,
    LegacyStatusFixture,
    TestContributions,
    TestSubjectSchema
  }

  alias Ecto.Adapters.SQL

  def install_registry! do
    authz =
      Bilimbi.Base.Authz.ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "base/workflow", otp_app: :bilimbi_base_workflow},
          payload: %{
            domains: %{"admin" => "Example"},
            verbs: ["view"],
            capabilities: ["admin.test.record.view"],
            company_directory: Bilimbi.Base.Workflow.TestCompanyDirectory
          }
        }
      ])

    snapshot = ContributionRegistry.build!([])
    snapshot = put_in(snapshot.consumers.authz, authz)
    workflow = ContributionValidator.validate_contributions!([entry()])
    ContributionRegistry.put_snapshot_for_test!(put_in(snapshot.consumers.workflow, workflow))
  end

  def entry,
    do: %{
      descriptor: %{
        id: "base/workflow",
        otp_app: :bilimbi_base_workflow,
        dependencies: [],
        graph_fingerprint: "workflow-test",
        contribution_provider: TestContributions
      },
      payload: TestContributions.contributions().workflow
    }

  def create_tables! do
    Bilimbi.Base.Tenancy.TestFixtures.create_tenants_table!()
    Bilimbi.Base.Tenancy.TestFixtures.insert_tenant!(%{id: 1})
    Bilimbi.Base.Tenancy.TestFixtures.insert_tenant!(%{id: 2, is_platform_operator: false})
    Bilimbi.Base.Authz.TestFixtures.create_authz_tables!()
    Bilimbi.Base.Audit.TestFixtures.create_audit_tables!()
    LegacyStatusFixture.create!(Repo, Bilimbi.Base.Database.DataCase.temporary_schema!())

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE base_workflow_subject_bindings (
        id bigserial PRIMARY KEY, tenant_id bigint NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
        flow varchar(255) NOT NULL, flow_id bigint NOT NULL, subject_type varchar(255) NOT NULL,
        subject_id varchar(255) NOT NULL, owner varchar(255) NOT NULL, created_at timestamp(0) NOT NULL,
        CONSTRAINT base_workflow_subject_binding_unique UNIQUE(flow, flow_id),
        CONSTRAINT base_workflow_subject_identity_unique UNIQUE(tenant_id, subject_type, subject_id)
      )
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE workflow_test_subjects (
        id bigserial PRIMARY KEY, tenant_id bigint NOT NULL, company_id bigint, status varchar(255), marker varchar(255)
      )
      """,
      []
    )
  end

  def subject!(attrs \\ %{}) do
    attrs = Map.merge(%{tenant_id: 1, company_id: 10, status: "draft", marker: "original"}, attrs)
    row = %TestSubjectSchema{} |> Ecto.Changeset.change(attrs) |> Repo.insert!()
    %{type: "example.record", id: row.id}
  end

  def state(id), do: Repo.get!(TestSubjectSchema, id)
end
