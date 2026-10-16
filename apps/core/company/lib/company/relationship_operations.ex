defmodule Bilimbi.Core.Company.RelationshipOperations do
  @moduledoc "Agent adapters over the existing relationship and role catalogue facades."
  @behaviour Bilimbi.Base.AgentApi.Operation
  alias Bilimbi.Base.Authz.AgentPolicy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Company.RelationshipCatalogue
  alias Bilimbi.Core.Company.Relationships

  @operations [
    {"relationship_role.list", :read, "list", [],
     "Search the platform-wide role catalogue, including retired roles."},
    {"relationship_role.get", :read, "list", ["role_id"],
     "Read a role and its direction/inverse labels."},
    {"relationship_role.create", :write, "create", ["code", "name", "inverse_name"],
     "Create a platform-wide role (platform operator only)."},
    {"relationship_role.update", :write, "update", ["role_id"],
     "Rename a role or its inverse, preserving IDs and historical links."},
    {"relationship_role.retire", :write, "update", ["role_id"],
     "Retire a role from new assignments; preserve existing relationships."},
    {"relationship.list", :read, "view", ["company_id"],
     "Read relationships from a company's perspective; related company has outgoing role."},
    {"relationship.get", :read, "view", ["company_id", "relationship_id"],
     "Read one company relationship."},
    {"relationship.create", :write, "update",
     ["company_id", "related_company_id", "relationship_type_id"],
     "Assign a role to the related company toward the source company. Roles grant no access."},
    {"relationship.update", :write, "update", ["company_id", "relationship_id"],
     "Update relationship effective dates, preserving its role and organisations."},
    {"relationship.end", :write, "update", ["company_id", "relationship_id"],
     "End a relationship on a date (default today), keeping it as dated history. A prospect becomes a customer by ending that role and creating the other."},
    {"relationship.unlink", :write, "update", ["company_id", "relationship_id"],
     "Remove a mistaken relationship entry from active lists while retaining history. Use relationship.end for a normal transition."}
  ]
  def declarations do
    Enum.map(@operations, fn {suffix, kind, capability, required, description} ->
      d = %{
        key: "core.company." <> suffix,
        title: String.replace(suffix, ".", " "),
        summary: description,
        keywords: ~w(vendor supplier customer partner role relationship),
        kind: kind,
        capability: "admin.company." <> capability,
        handler: __MODULE__,
        input: schema(suffix, required),
        output: %{"type" => if(String.ends_with?(suffix, ".list"), do: "array", else: "object")}
      }

      if kind == :write, do: Map.put(d, :safe_write, true), else: d
    end)
  end

  defp dates do
    date = %{
      "type" => "string",
      "maxLength" => 10,
      "description" => "ISO date (YYYY-MM-DD); an empty string clears this optional date."
    }

    %{"effective_from" => date, "effective_to" => date}
  end

  defp schema(suffix, required) do
    id = %{"type" => "integer", "minimum" => 1}
    text = %{"type" => "string", "maxLength" => 255}

    props =
      case suffix do
        "relationship_role.list" ->
          %{"search" => text}

        "relationship_role.get" ->
          %{"role_id" => id}

        "relationship_role.retire" ->
          %{"role_id" => id}

        "relationship_role.create" ->
          %{"code" => text, "name" => text, "inverse_name" => text, "description" => text}

        "relationship_role.update" ->
          %{
            "role_id" => id,
            "name" => text,
            "inverse_name" => text,
            "description" => text,
            "is_active" => %{"type" => "boolean"}
          }

        "relationship.list" ->
          %{"company_id" => id, "search" => text, "include_unlinked" => %{"type" => "boolean"}}

        "relationship.get" ->
          %{"company_id" => id, "relationship_id" => id}

        "relationship.unlink" ->
          %{"company_id" => id, "relationship_id" => id}

        "relationship.end" ->
          %{
            "company_id" => id,
            "relationship_id" => id,
            "effective_to" => %{
              "type" => "string",
              "maxLength" => 10,
              "description" => "ISO date (YYYY-MM-DD); defaults to today."
            }
          }

        "relationship.create" ->
          Map.merge(
            %{"company_id" => id, "related_company_id" => id, "relationship_type_id" => id},
            dates()
          )

        "relationship.update" ->
          Map.merge(%{"company_id" => id, "relationship_id" => id}, dates())
      end

    %{"type" => "object", "required" => required, "properties" => props}
  end

  @impl true
  def call("core.company.relationship_role.list", _scope, input) do
    with {:ok, roles} <- Company.list_relationship_types() do
      search = String.downcase(input["search"] || "")

      {:ok,
       Enum.filter(roles, &String.contains?(String.downcase(&1.name <> " " <> &1.code), search))}
    end
  end

  def call("core.company.relationship_role.get", _scope, input),
    do: Company.get_relationship_type(input["role_id"])

  def call("core.company.relationship.list", scope, input) do
    with {:ok, rows} <-
           Company.list_relationships(scope, input["company_id"],
             include_unlinked: Map.get(input, "include_unlinked", false)
           ) do
      search = String.downcase(input["search"] || "")

      {:ok,
       rows
       |> Enum.filter(
         &String.contains?(
           String.downcase(&1.type.name <> " " <> &1.type.code <> " " <> &1.other_company.name),
           search
         )
       )
       |> Enum.map(&read_model/1)}
    end
  end

  def call("core.company.relationship.get", scope, input) do
    with {:ok, rows} <-
           Company.list_relationships(scope, input["company_id"], include_unlinked: true) do
      case Enum.find(rows, &(&1.id == input["relationship_id"])) do
        nil -> {:error, :not_found}
        row -> {:ok, read_model(row)}
      end
    end
  end

  @impl true
  def preview("core.company.relationship_role." <> action, scope, input) do
    attrs = if action == "retire", do: %{"is_active" => false}, else: input
    RelationshipCatalogue.preview(scope, input["role_id"], attrs)
  end

  def preview("core.company.relationship." <> action, scope, input) do
    {action, input} =
      if action == "end",
        do: {"update", Map.merge(input, Relationships.ending_attrs(input))},
        else: {action, input}

    with :ok <- target_policy(scope, input["company_id"]),
         do:
           Relationships.preview(
             scope,
             input["company_id"],
             input["relationship_id"],
             action,
             input
           )
  end

  @impl true
  def commit("core.company.relationship_role." <> action, scope, input) do
    result =
      case action do
        "create" ->
          Company.create_relationship_type(scope, input)

        "update" ->
          Company.update_relationship_type(scope, input["role_id"], input)

        "retire" ->
          Company.update_relationship_type(scope, input["role_id"], %{"is_active" => false})
      end

    with {:ok, role} <- result, do: {:ok, %{record: role, path: "/companies/relationship-types"}}
  end

  def commit("core.company.relationship." <> action, scope, input) do
    with :ok <- target_policy(scope, input["company_id"]) do
      result =
        case action do
          "create" ->
            Company.create_relationship(scope, input["company_id"], input)

          "update" ->
            Company.update_relationship(
              scope,
              input["company_id"],
              input["relationship_id"],
              input
            )

          "end" ->
            Company.end_relationship(
              scope,
              input["company_id"],
              input["relationship_id"],
              input
            )

          "unlink" ->
            case Company.delete_relationship(scope, input["company_id"], input["relationship_id"]) do
              :ok -> {:ok, %{id: input["relationship_id"], unlinked: true}}
              error -> error
            end
        end

      with {:ok, row} <- result,
           do:
             {:ok,
              %{
                record: mutation_model(row),
                path: "/companies/#{input["company_id"]}/relationships"
              }}
    end
  end

  defp target_policy(scope, company_id) do
    with {:ok, _} <- Company.authorize_company_target(scope, company_id, "admin.company.update") do
      if AgentPolicy.writes_enabled_in_company?(scope, company_id),
        do: :ok,
        else: {:error, :writes_not_enabled}
    end
  end

  defp mutation_model(%{unlinked: true} = row), do: row

  defp mutation_model(row),
    do:
      Map.take(row, [
        :id,
        :company_id,
        :related_company_id,
        :relationship_type_id,
        :effective_from,
        :effective_to,
        :deleted_at
      ])

  defp read_model(row),
    do:
      Map.take(row, [
        :id,
        :direction,
        :role_label,
        :type,
        :other_company,
        :effective_from,
        :effective_to,
        :is_active,
        :unlinked_at
      ])
end
