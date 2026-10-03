defmodule Bilimbi.Base.Workflow.Web.ReferenceLiveTest do
  use BilimbiWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Bilimbi.Base.{Authz, Repo, Workflow}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Workflow.{ReferenceFlow, TestFixtures, TestSubjectSchema}
  alias Bilimbi.Core.Company.TestFixtures, as: CompanyFixtures
  alias Bilimbi.Core.User.TestFixtures, as: UserFixtures

  setup %{conn: conn} do
    UserFixtures.create_user_tables!()
    CompanyFixtures.insert_tenant!(%{id: 41})
    CompanyFixtures.insert_company!(%{id: 73, tenant_id: 41})
    UserFixtures.insert_user!(%{id: 91, company_id: 73})
    TestFixtures.create_reference_tables!()
    installed = ContributionRegistry.snapshot!()
    install_reference_registry!()
    on_exit(fn -> ContributionRegistry.put_snapshot_for_test!(installed) end)
    assert {:ok, :seeded} = Workflow.seed_definitions()

    {:ok,
     %{
       conn: conn,
       subject_ref: TestFixtures.reference_subject!(),
       scope: authenticated_scope!()
     }}
  end

  test "renders action panel and history, then executes its work-bound human action", %{
    conn: conn,
    subject_ref: subject
  } do
    scope = authenticated_scope!()

    assert {:ok, :stored} =
             Authz.put_principal_capability(
               scope,
               73,
               :user,
               91,
               "admin.reference.record.approve",
               true
             )

    assert {:ok, _transition} = Workflow.transition(scope, subject, "review")

    {:ok, run} =
      Workflow.start_run(scope, "reference.review", subject,
        idempotency_key: "reference:attempt:1"
      )

    {:ok, view, _html} = conn |> log_in_as() |> live("/workflow/reference/#{subject.id}")

    assert has_element?(view, "#workflow-reference-actions")
    assert has_element?(view, "#workflow-reference-history")
    assert has_element?(view, "#workflow-reference-work", "available")
    execute = "#execute-workflow-action-0"
    assert has_element?(view, execute)
    view |> element(execute) |> render_click()

    assert Repo.get!(TestSubjectSchema, subject.id).marker == "human-action"
    assert has_element?(view, "#workflow-reference-history", "review")

    assert has_element?(view, "#workflow-reference-failure", "Workflow could not complete") ==
             false

    assert {:ok,
            %{
              run: %{status: "completed"},
              work_items: [%{status: "completed", result_ref: result_ref}]
            }} =
             Workflow.get_run(scope, run.id)

    assert result_ref == "reference:#{subject.id}"
  end

  defp authenticated_scope! do
    {:ok, base_scope} = Bilimbi.Base.Tenancy.scope(41)
    Authentication.sign_in(base_scope, 91, 73)
  end

  defp install_reference_registry! do
    provider = ReferenceFlow.contributions().workflow
    workflow_entry = TestFixtures.entry()
    workflow_entry = %{workflow_entry | payload: provider}

    workflow =
      Bilimbi.Base.Workflow.ContributionValidator.validate_contributions!([workflow_entry])

    authz =
      Bilimbi.Base.Authz.ContributionValidator.validate_contributions!([
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
      ContributionRegistry.snapshot!()
      |> put_in([:consumers, :authz], authz)
      |> put_in([:consumers, :workflow], workflow)

    ContributionRegistry.put_snapshot_for_test!(snapshot)
  end
end
