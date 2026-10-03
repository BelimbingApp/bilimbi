defmodule Bilimbi.Base.Workflow.ReferenceAuthorizationTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.{Authz, Workflow}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Workflow.{BindingSchema, ReferenceFlow, RunSchema}

  import Bilimbi.Base.Workflow.TestFixtures

  setup do
    create_tables!()
    install_reference_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    system = Authz.TestFixtures.scope()
    scope = Authentication.sign_in(system, 7, 10)

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               scope,
               10,
               :user,
               7,
               "admin.reference.record.approve",
               true
             )

    %{
      scope: scope,
      system: system,
      owned: reference_subject!(%{tenant_id: 1, company_id: 10}),
      company_less: reference_subject!(%{tenant_id: 1, company_id: nil})
    }
  end

  test "a reference subject without a company is refused", %{
    scope: scope,
    system: system,
    owned: owned,
    company_less: company_less
  } do
    assert {:error, :missing_capability} = Workflow.history(scope, company_less)
    assert {:error, :missing_capability} = Workflow.adopt_subject(scope, company_less)

    assert {:error, :missing_capability} =
             Workflow.start_run(scope, "reference.review", company_less,
               idempotency_key: "reference:company-less"
             )

    assert Repo.all(BindingSchema) == []
    assert Repo.aggregate(RunSchema, :count) == 0

    stranger = Authentication.sign_in(system, 9, 10)
    assert {:error, :missing_capability} = Workflow.history(stranger, owned)
    assert {:ok, %{entries: []}} = Workflow.history(scope, owned)
  end

  defp install_reference_registry! do
    workflow_entry = %{entry() | payload: ReferenceFlow.contributions().workflow}

    workflow =
      Bilimbi.Base.Workflow.ContributionValidator.validate_contributions!([workflow_entry])

    authz =
      Authz.ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "domain/reference", otp_app: :bilimbi_base_workflow},
          payload: %{
            domains: %{"admin" => "Reference"},
            verbs: ["approve"],
            capabilities: ["admin.reference.record.approve"],
            company_directory: Bilimbi.Base.Workflow.ReferenceCompanyDirectory
          }
        }
      ])

    snapshot =
      ContributionRegistry.build!([])
      |> put_in([:consumers, :authz], authz)
      |> put_in([:consumers, :workflow], workflow)

    ContributionRegistry.put_snapshot_for_test!(snapshot)
  end
end
