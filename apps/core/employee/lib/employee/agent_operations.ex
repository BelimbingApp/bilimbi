defmodule Bilimbi.Core.Employee.AgentOperations do
  @moduledoc """
  The Employee operations agents may call (ADR 0021), each a thin adapter
  over this module's facade with the scope it is given.

  Their declarations live in `Bilimbi.Core.Employee.Contributions`, and the
  capability each stands on is the one the matching page asks for:
  `admin.employee.list` for the Employees list and `admin.employee.create`
  for creating a person. An employer target is authorized through Company,
  like the form's selector. Omitting a list target uses the signed-in company;
  targets never replace the scope's authenticated person, company or tenant.
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
      create_declaration(),
      %{
        key: "core.employee.person_identity",
        title: "Read legacy identity mapping",
        summary:
          "Resolve a retained legacy employee to its Core Person and affiliation IDs. Requires contact read permission too.",
        kind: :read,
        capability: "admin.employee.list",
        handler: __MODULE__,
        input: %{
          "type" => "object",
          "required" => ["employee_id"],
          "properties" => %{"employee_id" => %{"type" => "integer", "minimum" => 1}}
        },
        output: %{"type" => "object"}
      },
      %{
        key: "core.employee.list",
        title: "List legacy HR records (deprecated)",
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
            "employer_company_id" => %{
              "type" => "integer",
              "minimum" => 1,
              "description" =>
                "Optional employer to search, authorized like the company selector; defaults to your signed-in company."
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

  defp create_declaration do
    text = %{"type" => "string", "maxLength" => 255}

    %{
      key: "core.employee.create",
      title: "Create legacy HR record (deprecated)",
      summary:
        "Deprecated HR compatibility. Requires confirmed employment and an HR number; use core.person.contact.create for namecards.",
      keywords: ["add", "person", "people", "employer"],
      kind: :write,
      safe_write: true,
      capability: "admin.employee.create",
      handler: __MODULE__,
      input: %{
        "type" => "object",
        "required" => ["employer_company_id", "employee_number", "full_name"],
        "properties" => %{
          "employer_company_id" => %{"type" => "integer", "minimum" => 1},
          "employee_number" => text,
          "full_name" => text,
          "short_name" => text,
          "designation" => text,
          "employee_type" => text,
          "job_description" => %{"type" => "string", "maxLength" => 10_000},
          "email" => text,
          "mobile_number" => text,
          "status" => %{
            "type" => "string",
            "enum" => ~w(pending probation active inactive terminated)
          }
        }
      },
      output: %{"type" => "object", "description" => "Created employee and its Bilimbi URL."}
    }
  end

  @impl true
  def preview("core.employee.create", %Scope{} = scope, input) do
    with :ok <- authorize_employer(scope, input["employer_company_id"]),
         {:ok, employee} <-
           Employee.preview_create_employee(
             scope,
             input["employer_company_id"],
             Map.delete(input, "employer_company_id")
           ) do
      changes =
        employee
        |> Map.from_struct()
        |> Map.drop([:id, :created_at, :updated_at])
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
        |> Enum.sort()
        |> Enum.map(fn {k, v} -> %{field: Atom.to_string(k), from: nil, to: v} end)

      {:ok, %{summary: "Create person at their employer", changes: changes}}
    end
  end

  @impl true
  def commit("core.employee.create", %Scope{} = scope, input) do
    with :ok <- authorize_employer(scope, input["employer_company_id"]),
         {:ok, employee} <-
           Employee.create_employee(
             scope,
             input["employer_company_id"],
             Map.delete(input, "employer_company_id")
           ) do
      path = "/employees/#{employee.id}"

      path =
        if employee.company_id == Scope.actor(scope).company_id,
          do: path,
          else: path <> "?employer_company_id=#{employee.company_id}"

      {:ok, %{record: employee, path: path}}
    end
  end

  defp authorize_employer(scope, company_id) do
    with {:ok, _company} <-
           Bilimbi.Core.Company.authorize_company_target(
             scope,
             company_id,
             "admin.employee.create"
           ) do
      if Bilimbi.Base.Authz.AgentPolicy.writes_enabled_in_company?(scope, company_id),
        do: :ok,
        else: {:error, :writes_not_enabled}
    end
  end

  @impl true
  def call("core.employee.person_identity", scope, input),
    do: Employee.person_identity(scope, input["employee_id"])

  def call("core.employee.list", %Scope{} = scope, input) do
    %Actor{company_id: signed_in_company_id} = Scope.actor(scope)
    company_id = Map.get(input, "employer_company_id", signed_in_company_id)

    options = [
      page: Map.get(input, "page", 1),
      page_size: Map.get(input, "page_size", 25),
      search: Map.get(input, "search", "")
    ]

    with {:ok, _} <-
           Bilimbi.Core.Company.authorize_company_target(scope, company_id, "admin.employee.list") do
      list_page(scope, company_id, options)
    end
  end

  defp list_page(scope, company_id, options) do
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
