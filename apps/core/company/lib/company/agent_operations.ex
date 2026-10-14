defmodule Bilimbi.Core.Company.AgentOperations do
  @moduledoc """
  The Company operations agents may call (ADR 0021), each a thin adapter
  over this module's facade with the scope it is given.

  Their declarations live in `Bilimbi.Core.Company.Contributions`, and the
  capability each stands on is the one the matching page asks for:
  `admin.company.list` for the Companies list, `admin.company.view` for a
  company's page. The facade builds every row through its read models, so
  a field the reader may not see arrives as a `Restricted` marker.
  """

  @behaviour Bilimbi.Base.AgentApi.Operation

  alias Bilimbi.Base.AgentApi.Page
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.Schema

  @doc "The operation declarations for `Bilimbi.Core.Company.Contributions`."
  @spec declarations() :: [map()]
  def declarations do
    [
      create_declaration(),
      %{
        key: "core.company.list",
        title: "List companies",
        summary:
          "Find companies of your tenant by name, code, legal name, email or jurisdiction, " <>
            "one page at a time, with the fields you may see.",
        keywords: ["find", "search", "browse", "organisation", "business", "firm"],
        kind: :read,
        capability: "admin.company.list",
        input: %{
          "type" => "object",
          "properties" => %{
            "search" => %{
              "type" => "string",
              "maxLength" => 200,
              "description" =>
                "Words matched against name, code, legal name, email and jurisdiction."
            },
            "status" => %{"type" => "string", "enum" => Schema.statuses()},
            "page" => %{"type" => "integer", "minimum" => 1},
            "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
          }
        },
        output: %{
          "type" => "array",
          "description" =>
            "Companies with id, name, code, legal_name, status, jurisdiction, " <>
              "parent_id, parent_name and primary."
        },
        handler: __MODULE__
      },
      %{
        key: "core.company.get",
        title: "Read a company",
        summary: "One company of your tenant by id, with the fields you may see.",
        keywords: ["show", "detail", "organisation", "business", "firm"],
        kind: :read,
        capability: "admin.company.view",
        input: %{
          "type" => "object",
          "required" => ["company_id"],
          "properties" => %{"company_id" => %{"type" => "integer", "minimum" => 1}}
        },
        output: %{
          "type" => "object",
          "description" =>
            "The company's identity, legal and contact facts. A field you may not see " <>
              "reads {\"restricted\": true}."
        },
        handler: __MODULE__
      }
    ]
  end

  defp create_declaration do
    text = %{"type" => "string", "maxLength" => 255}

    %{
      key: "core.company.create",
      title: "Create a company",
      summary: "Create an organisation in your tenant after searching for an existing company.",
      keywords: ["add", "organisation", "business"],
      kind: :write,
      safe_write: true,
      capability: "admin.company.create",
      handler: __MODULE__,
      input: %{
        "type" => "object",
        "required" => ["name"],
        "properties" => %{
          "name" => text,
          "code" => text,
          "legal_name" => text,
          "registration_number" => text,
          "tax_id" => text,
          "jurisdiction" => %{"type" => "string", "maxLength" => 2},
          "email" => text,
          "website" => text,
          "status" => %{"type" => "string", "enum" => Schema.initial_statuses()}
        }
      },
      output: %{"type" => "object", "description" => "Created company and its Bilimbi URL."}
    }
  end

  @impl true
  def preview("core.company.create", %Scope{} = scope, input) do
    with {:ok, company} <- Company.preview_create_company(scope, input) do
      changes =
        company
        |> Map.from_struct()
        |> Map.drop([:id, :tenant_id])
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
        |> Enum.sort()
        |> Enum.map(fn {k, v} -> %{field: Atom.to_string(k), from: nil, to: v} end)

      {:ok, %{summary: "Create company", changes: changes}}
    end
  end

  @impl true
  def commit("core.company.create", %Scope{} = scope, input) do
    with {:ok, company} <- Company.create_company(scope, input) do
      {:ok, %{record: company, path: "/companies/#{company.id}"}}
    end
  end

  @impl true
  def call("core.company.list", %Scope{} = scope, input) do
    options =
      [
        page: Map.get(input, "page", 1),
        page_size: Map.get(input, "page_size", 25),
        search: Map.get(input, "search", ""),
        status_filter: Map.get(input, "status", :all)
      ]

    with {:ok, page} <- Company.list_administration_page(scope, options) do
      {:ok,
       %Page{
         entries: page.entries,
         page: page.page,
         page_size: page.page_size,
         total: page.total_entries
       }}
    end
  end

  def call("core.company.get", %Scope{} = scope, %{"company_id" => company_id}) do
    Company.get_company(scope, company_id)
  end
end
