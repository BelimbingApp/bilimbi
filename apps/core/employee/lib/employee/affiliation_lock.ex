defmodule Bilimbi.Core.Employee.AffiliationLock do
  @moduledoc false

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.LiveCompanyProof
  alias Bilimbi.Core.Employee.AffiliationProof
  alias Bilimbi.Core.Employee.Schema

  @platform_orchestrator_number "SYS-001"
  @platform_orchestrator_type "agent"

  @spec lock(Scope.t(), term(), term()) ::
          {:ok, AffiliationProof.t()}
          | {:error, :invariant_violation | :not_found | :transaction_required}
  def lock(%Scope{} = scope, company_id, employee_id) do
    cond do
      not Repo.in_transaction?() ->
        {:error, :transaction_required}

      not positive_id?(company_id) or not positive_id?(employee_id) ->
        {:error, :not_found}

      true ->
        lock_in_transaction(scope, company_id, employee_id)
    end
  end

  defp lock_in_transaction(scope, company_id, employee_id) do
    with {:ok, %LiveCompanyProof{id: ^company_id}} <-
           Company.lock_live_company(scope, company_id),
         %Schema{} = employee <- lock_employee(company_id, employee_id),
         {:ok, proof} <- reprove_affiliation(employee, company_id, employee_id) do
      {:ok, proof}
    else
      nil ->
        {:error, :not_found}

      {:error, reason}
      when reason in [:invariant_violation, :not_found, :transaction_required] ->
        {:error, reason}
    end
  end

  defp lock_employee(company_id, employee_id) do
    Repo.one(
      from(employee in Schema,
        where: employee.id == ^employee_id and employee.company_id == ^company_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp reprove_affiliation(
         %Schema{
           id: employee_id,
           company_id: company_id,
           employee_number: @platform_orchestrator_number,
           employee_type: @platform_orchestrator_type
         },
         company_id,
         employee_id
       ),
       do: {:error, :invariant_violation}

  defp reprove_affiliation(
         %Schema{id: employee_id, company_id: company_id},
         company_id,
         employee_id
       ),
       do: {:ok, AffiliationProof.from_ids(employee_id, company_id)}

  defp reprove_affiliation(%Schema{}, _company_id, _employee_id), do: {:error, :not_found}

  defp positive_id?(id), do: is_integer(id) and id > 0
end
