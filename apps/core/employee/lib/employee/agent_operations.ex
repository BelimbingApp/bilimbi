defmodule Bilimbi.Core.Employee.AgentOperations do
  @moduledoc """
  The Employee operations agents may call (ADR 0021), each a thin adapter
  over this module's facade with the scope it is given.

  Their declarations live in `Bilimbi.Core.Employee.Contributions`, and the
  capability each stands on is the one the matching page asks for:
  `admin.employee.list` for the Employees list. Like that page, the list is
  the employees of the company the person signed in at, which the scope
  names; no company is taken from input.
  """

  @behaviour Bilimbi.Base.AgentApi.Operation

  alias Bilimbi.Base.AgentApi.Page
  alias Bilimbi.Base.Tenancy.Actor
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Employee

  @doc "The operation declarations for `Bilimbi.Core.Employee.Contributions`."
  @spec declarations() :: [map()]
  def declarations do
    [
      %{
        key: "core.employee.list",
        title: "List employees",
        summary:
          "Find employees of the company you signed in at by name, number, email, " <>
            "designation or job description, one page at a time.",
        keywords: ["find", "search", "browse", "staff", "people", "worker", "personnel"],
        kind: :read,
        capability: "admin.employee.list",
        input: %{
          "type" => "object",
          "properties" => %{
            "search" => %{
              "type" => "string",
              "maxLength" => 200,
              "description" =>
                "Words matched against full name, short name, employee number, email, " <>
                  "designation and job description."
            },
            "page" => %{"type" => "integer", "minimum" => 1},
            "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
          }
        },
        output: %{
          "type" => "array",
          "description" =>
            "Employees with id, employee_number, full_name, short_name, designation, " <>
              "department_id, employee_type, employee_type_label, email and status."
        },
        handler: __MODULE__
      }
    ]
  end

  @impl true
  def call("core.employee.list", %Scope{} = scope, input) do
    %Actor{company_id: company_id} = Scope.actor(scope)

    options = [
      page: Map.get(input, "page", 1),
      page_size: Map.get(input, "page_size", 25),
      search: Map.get(input, "search", "")
    ]

    case Employee.list_administration_page(scope, company_id, options) do
      {:ok, page} ->
        {:ok,
         %Page{
           entries: page.entries,
           page: page.page,
           page_size: page.page_size,
           total: page.total_entries
         }}

      {:error, :company_not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
