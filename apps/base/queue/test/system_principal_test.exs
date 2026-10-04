defmodule Bilimbi.Base.Queue.SystemPrincipalTest do
  @moduledoc """
  A worker that declares a system principal runs only as that principal: in
  the tenant and company it was enqueued for, with its captured writes
  attributed to the principal. Nothing else can make a job run as a
  principal, and a principal's job never runs as anything else.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Audit.Context, as: AuditContext
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Queue
  alias Bilimbi.Base.Queue.Execution
  alias Bilimbi.Base.Queue.JobRef
  alias Bilimbi.Base.Queue.TestWorkers.ActingFor
  alias Bilimbi.Base.Queue.TestWorkers.LineImport
  alias Bilimbi.Base.Queue.TestWorkers.OtherImport
  alias Bilimbi.Base.Queue.TestWorkers.UniqueImport
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Base.Tenancy.SystemPrincipals.ContributionValidator

  import Bilimbi.Base.Tenancy.TestFixtures

  setup do
    create_tenants_table!()
    insert_tenant!(%{id: 41})
    {:ok, scope} = Tenancy.scope(41)

    install_principals!([
      {"ext/coating", :bilimbi_base_queue, "coating.line_import"},
      {"ext/elsewhere", :bilimbi_base_tenancy, "coating.other_import"}
    ])

    on_exit(&ContributionRegistry.clear_for_test!/0)

    %{scope: scope}
  end

  test "the job runs as its declared principal in the enqueued company", %{scope: scope} do
    assert {:ok, %JobRef{id: id}} =
             Queue.enqueue_as_system(scope, 10, LineImport, %{"value" => 1})

    job = Repo.get!(Oban.Job, id)
    assert job.args == %{"value" => 1}

    assert :ok = perform(LineImport, job)
    assert_received {:performed, %Execution{scope: %Scope{} = job_scope}, audit_context}

    assert Scope.tenant_id(job_scope) == 41

    assert %Actor{
             type: :system,
             system_principal: "coating.line_import",
             company_id: 10,
             user_id: nil
           } =
             Scope.actor(job_scope)

    assert %AuditContext{
             actor_type: "system",
             actor_id: 0,
             system_principal: "coating.line_import",
             company_id: 10,
             tenant_id: 41
           } = audit_context

    assert AuditContext.get() == %AuditContext{}
  end

  test "whoever enqueued it, the job is not them", %{scope: scope} do
    signed_in = Authentication.sign_in(scope, 7, 10)

    {:ok, %JobRef{id: id}} = Queue.enqueue_as_system(signed_in, 10, LineImport, %{"value" => 1})
    assert :ok = perform(LineImport, Repo.get!(Oban.Job, id))

    assert_received {:performed, %Execution{scope: job_scope}, %AuditContext{actor_id: 0}}
    assert %Actor{type: :system, user_id: nil} = Scope.actor(job_scope)
  end

  test "a principal's worker runs only through enqueue_as_system/4", %{scope: scope} do
    assert {:error, :system_principal_worker} = Queue.enqueue(LineImport, %{"value" => 1})

    assert {:error, :system_principal_worker} =
             scope
             |> Authentication.sign_in(7, 10)
             |> Queue.enqueue_for(LineImport, %{"value" => 1})

    assert {:error, :not_system_principal_worker} =
             Queue.enqueue_as_system(scope, 10, ActingFor, %{"value" => 1})

    assert {:error, :unsupported_worker} =
             Queue.enqueue_as_system(scope, 10, Enum, %{"value" => 1})

    assert Repo.aggregate(Oban.Job, :count) == 0
  end

  test "an undeclared name, or another module's name, is refused", %{scope: scope} do
    install_principals!([{"ext/elsewhere", :bilimbi_base_tenancy, "coating.other_import"}])

    assert {:error, :undeclared_system_principal} =
             Queue.enqueue_as_system(scope, 10, LineImport, %{"value" => 1})

    # OtherImport names a principal declared by a module it does not belong to.
    assert {:error, :undeclared_system_principal} =
             Queue.enqueue_as_system(scope, 10, OtherImport, %{"value" => 1})

    assert Repo.aggregate(Oban.Job, :count) == 0
  end

  test "a company that is not a positive ID is refused", %{scope: scope} do
    for company_id <- [0, -1, nil, "10"] do
      assert {:error, :invalid_company} =
               Queue.enqueue_as_system(scope, company_id, LineImport, %{"value" => 1})
    end
  end

  test "a unique worker cannot run as a principal", %{scope: scope} do
    assert {:error, :unique_worker} =
             Queue.enqueue_as_system(scope, 10, UniqueImport, %{"value" => 1})
  end

  test "a principal undeclared before the job runs cancels it", %{scope: scope} do
    {:ok, %JobRef{id: id}} = Queue.enqueue_as_system(scope, 10, LineImport, %{"value" => 1})

    install_principals!([])

    assert {:cancel, :system_principal_refused} = perform(LineImport, Repo.get!(Oban.Job, id))
    refute_received {:performed, _execution, _context}
  end

  test "a tampered, missing, or borrowed token never runs as the principal", %{scope: scope} do
    {:ok, %JobRef{id: id}} = Queue.enqueue_as_system(scope, 10, LineImport, %{"value" => 1})
    job = Repo.get!(Oban.Job, id)
    token = job.meta["bilimbi_system_principal"]
    {:ok, user_token} = scope |> Authentication.sign_in(7, 10) |> Authentication.delegate()

    for meta <- [
          %{job.meta | "bilimbi_system_principal" => token <> "x"},
          %{job.meta | "bilimbi_system_principal" => user_token},
          %{job.meta | "bilimbi_system_principal" => %{"name" => "coating.line_import"}},
          Map.delete(job.meta, "bilimbi_system_principal"),
          Map.put(job.meta, "bilimbi_delegated_actor", user_token)
        ] do
      assert {:cancel, :system_principal_unavailable} = perform(LineImport, %{job | meta: meta})
      refute_received {:performed, _execution, _context}
    end

    # An ordinary worker handed a principal's token runs as nobody's principal.
    assert {:cancel, :delegated_actor_unavailable} = perform(ActingFor, job)
    refute_received {:performed, _execution}
  end

  test "a token for one principal does not run another principal's worker", %{scope: scope} do
    install_principals!([
      {"ext/coating", :bilimbi_base_queue, "coating.line_import"},
      {"ext/coating-other", :bilimbi_base_queue, "coating.other_import"}
    ])

    {:ok, %JobRef{id: id}} = Queue.enqueue_as_system(scope, 10, LineImport, %{"value" => 1})
    job = Repo.get!(Oban.Job, id)

    assert {:cancel, :system_principal_refused} = perform(OtherImport, job)
    refute_received {:performed, _execution, _context}
  end

  defp perform(worker, job), do: worker.__queue_worker__().adapter.perform(job)

  defp install_principals!(declarations) do
    entries =
      Enum.map(declarations, fn {id, otp_app, name} ->
        %{
          descriptor: %{id: id, otp_app: otp_app},
          payload: [
            %{
              name: name,
              description: "Imports records.",
              capabilities: ["factory.material.import"]
            }
          ]
        }
      end)

    ContributionRegistry.put_consumers_for_test!(
      %{
        actor_verifier: nil,
        system_principals: ContributionValidator.validate_contributions!(entries)
      },
      nil
    )
  end
end
