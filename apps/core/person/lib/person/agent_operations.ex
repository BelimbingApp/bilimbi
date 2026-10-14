defmodule Bilimbi.Core.Person.AgentOperations do
  @moduledoc "Supported identity/contact and affiliation operations, independent of People."
  @behaviour Bilimbi.Base.AgentApi.Operation
  alias Bilimbi.Base.AgentApi.Page
  alias Bilimbi.Base.Authz.AgentPolicy
  alias Bilimbi.Core.Person

  @operations [
    {"core.person.list", :list, :read, "list",
     "Search people by name, email or phone before creating."},
    {"core.person.get", :get, :read, "view", "Read a person and their retained affiliations."},
    {"core.person.create", :create, :write, "create",
     "Create identity and contact details without HR or a login."},
    {"core.person.contact.create", :contact, :write, "create",
     "Create a person and their company affiliation from a namecard."},
    {"core.person.update", :update, :write, "update",
     "Update a person's identity and personal contact details."},
    {"core.person.retire", :retire, :write, "update",
     "Retire a person from active searches, preserving affiliations and HR references."},
    {"core.person.affiliation.list", :affiliations, :read, "view",
     "Read retained affiliations, including unlinked history."},
    {"core.person.affiliation.link", :link, :write, "update",
     "Affiliate an existing person with a company, with title and company contact details."},
    {"core.person.affiliation.update", :affiliation_update, :write, "update",
     "Update title and company contact details without changing HR facts."},
    {"core.person.affiliation.unlink", :unlink, :write, "update",
     "Unlink an affiliation while preserving its identity and history."}
  ]

  def declarations do
    Enum.map(@operations, fn {key, action, kind, capability, description} ->
      declaration = %{
        key: key,
        title: description,
        summary: description,
        keywords: ~w(person contact namecard affiliation vendor),
        kind: kind,
        capability: "admin.person.#{capability}",
        handler: __MODULE__,
        input: input(action),
        output: %{
          "type" => if(action == :list or action == :affiliations, do: "array", else: "object"),
          "description" =>
            "Core identity/contact facts and stable person/affiliation identifiers; no HR fields or account grants."
        }
      }

      if kind == :write, do: Map.put(declaration, :safe_write, true), else: declaration
    end)
  end

  defp input(action) do
    id = %{"type" => "integer", "minimum" => 1}
    text = %{"type" => "string", "maxLength" => 255}

    {required, fields} =
      case action do
        :list ->
          {[],
           %{
             "search" => text,
             "page" => id,
             "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
           }}

        :get ->
          {["person_id"], %{"person_id" => id}}

        :affiliations ->
          {["person_id"], %{"person_id" => id}}

        :retire ->
          {["person_id"], %{"person_id" => id}}

        :unlink ->
          {["person_id", "affiliation_id"], %{"person_id" => id, "affiliation_id" => id}}

        :create ->
          {["full_name"], %{"full_name" => text, "email" => text, "phone" => text}}

        :update ->
          {["person_id"],
           %{"person_id" => id, "full_name" => text, "email" => text, "phone" => text}}

        :contact ->
          {["full_name", "company_id"],
           %{
             "full_name" => text,
             "company_id" => id,
             "title" => text,
             "email" => text,
             "phone" => text
           }}

        :link ->
          {["person_id", "company_id"],
           %{
             "person_id" => id,
             "company_id" => id,
             "title" => text,
             "email" => text,
             "phone" => text
           }}

        :affiliation_update ->
          {["person_id", "affiliation_id"],
           %{
             "person_id" => id,
             "affiliation_id" => id,
             "title" => text,
             "email" => text,
             "phone" => text
           }}
      end

    %{"type" => "object", "required" => required, "properties" => fields}
  end

  @impl true
  def call("core.person.list", scope, input) do
    with {:ok, page} <-
           Person.list(scope,
             search: input["search"] || "",
             page: input["page"] || 1,
             page_size: input["page_size"] || 25
           ),
         do: {:ok, struct(Page, page)}
  end

  def call("core.person.get", scope, input), do: Person.get(scope, input["person_id"])

  def call("core.person.affiliation.list", scope, input),
    do: Person.affiliations(scope, input["person_id"])

  @impl true
  def preview(key, scope, input) do
    with :ok <- target_write_policy(scope, input, action(key)),
         do: Person.preview(scope, action(key), input)
  end

  @impl true
  def commit(key, scope, input) do
    with :ok <- target_write_policy(scope, input, action(key)),
         {:ok, row} <- perform(action(key), scope, input) do
      id = input["person_id"] || (row[:person] && row.person.id) || row.id
      {:ok, %{record: row, path: "/contacts/#{id}"}}
    end
  end

  defp perform(:create, scope, input), do: Person.create(scope, input)

  defp perform(:contact, scope, input),
    do: Person.create_contact(scope, input["company_id"], input)

  defp perform(:update, scope, input), do: Person.update(scope, input["person_id"], input)
  defp perform(:retire, scope, input), do: Person.retire(scope, input["person_id"])

  defp perform(:link, scope, input),
    do: Person.link(scope, input["person_id"], input["company_id"], input)

  defp perform(:affiliation_update, scope, input),
    do: Person.update_affiliation(scope, input["person_id"], input["affiliation_id"], input)

  defp perform(:unlink, scope, input),
    do: Person.unlink(scope, input["person_id"], input["affiliation_id"])

  defp target_write_policy(scope, input, operation_action) do
    capability =
      if operation_action == :contact, do: "admin.person.create", else: "admin.person.update"

    result =
      cond do
        input["affiliation_id"] ->
          Person.affiliation_target(scope, input["person_id"], input["affiliation_id"])

        input["company_id"] ->
          Person.company_target(scope, input["company_id"], capability)

        true ->
          {:ok, nil}
      end

    with {:ok, company_id} <- result do
      if company_id && not AgentPolicy.writes_enabled_in_company?(scope, company_id),
        do: {:error, :writes_not_enabled},
        else: :ok
    end
  end

  defp action(key),
    do: Enum.find_value(@operations, fn {k, action, _, _, _} -> if k == key, do: action end)
end
