defmodule Bilimbi.Base.Audit do
  @moduledoc """
  Public API for durable mutation and action facts.

  Tenant identity is never taken from the attributes map. Scoped recording
  derives `tenant_id` from a `Bilimbi.Base.Tenancy.Scope`. Unscoped recording
  (`:unscoped`) forces `tenant_id` to null. `company_id` and the actor pair
  are caller-assigned because rows outlive their subjects and have no foreign
  keys. Listing is tenant-scoped: a scope is required, and null-tenant rows
  are invisible to every tenant.
  """

  import Ecto.Query

  alias Bilimbi.Base.Audit.Action
  alias Bilimbi.Base.Audit.ActionSchema
  alias Bilimbi.Base.Audit.Mutation
  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Audit.Page
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope

  @default_page_size 25
  @mutation_sort_fields [:occurred_at, :actor_type, :event, :auditable_type, :trace_id]
  @action_sort_fields [:occurred_at, :actor_type, :event, :url, :trace_id]

  @spec record_mutation(Scope.t() | :unscoped, map()) ::
          {:ok, Mutation.t()} | {:error, Ecto.Changeset.t()}
  def record_mutation(%Scope{} = scope, attributes) when is_map(attributes) do
    persist_mutation(attributes, Scope.tenant_id(scope))
  end

  def record_mutation(:unscoped, attributes) when is_map(attributes) do
    persist_mutation(attributes, nil)
  end

  @spec record_action(Scope.t() | :unscoped, map()) ::
          {:ok, Action.t()} | {:error, Ecto.Changeset.t()}
  def record_action(%Scope{} = scope, attributes) when is_map(attributes) do
    persist_action(attributes, Scope.tenant_id(scope))
  end

  def record_action(:unscoped, attributes) when is_map(attributes) do
    persist_action(attributes, nil)
  end

  @doc "Lists all mutations for the scope without pagination."
  @spec list_mutations(Scope.t()) :: {:ok, [Mutation.t()]}
  def list_mutations(%Scope{} = scope) do
    mutations =
      from(mutation in Tenancy.scope_query(MutationSchema, scope),
        order_by: [asc: mutation.occurred_at, asc: mutation.id]
      )
      |> Repo.all()
      |> Enum.map(&Mutation.from_schema/1)

    {:ok, mutations}
  end

  @doc "Lists mutations for the scope through a bounded administration page."
  @spec list_mutations(Scope.t(), keyword()) :: Page.t(Mutation.t())
  def list_mutations(%Scope{} = scope, opts) when is_list(opts) do
    opts =
      Keyword.validate!(opts,
        page: 1,
        page_size: @default_page_size,
        search: nil,
        event: nil,
        sort_by: :occurred_at,
        sort_dir: :desc
      )

    base_query =
      MutationSchema
      |> Tenancy.scope_query(scope)
      |> maybe_search_mutations(opts[:search])
      |> maybe_filter_mutation_event(opts[:event])

    sort_field = validate_sort_field(opts[:sort_by], @mutation_sort_fields, :occurred_at)
    sort_dir = validate_sort_dir(opts[:sort_dir])

    ordered_query =
      base_query
      |> order_by_mutation(sort_field, sort_dir)

    page_query(
      base_query,
      ordered_query,
      opts,
      fn rows -> Enum.map(rows, &Mutation.from_schema/1) end
    )
  end

  @doc "Lists all actions for the scope without pagination."
  @spec list_actions(Scope.t()) :: {:ok, [Action.t()]}
  def list_actions(%Scope{} = scope) do
    actions =
      from(action in Tenancy.scope_query(ActionSchema, scope),
        order_by: [asc: action.occurred_at, asc: action.id]
      )
      |> Repo.all()
      |> Enum.map(&Action.from_schema/1)

    {:ok, actions}
  end

  @doc "Lists actions for the scope through a bounded administration page."
  @spec list_actions(Scope.t(), keyword()) :: Page.t(Action.t())
  def list_actions(%Scope{} = scope, opts) when is_list(opts) do
    opts =
      Keyword.validate!(opts,
        page: 1,
        page_size: @default_page_size,
        search: nil,
        actor_type: nil,
        event_family: nil,
        result: nil,
        diagnostics: "hide",
        sort_by: :occurred_at,
        sort_dir: :desc
      )

    base_query =
      ActionSchema
      |> Tenancy.scope_query(scope)
      |> maybe_search_actions(opts[:search])
      |> maybe_filter_action_actor_type(opts[:actor_type])
      |> maybe_filter_action_family(opts[:event_family])
      |> maybe_filter_action_result(opts[:result])
      |> maybe_filter_action_diagnostics(opts[:diagnostics])

    sort_field = validate_sort_field(opts[:sort_by], @action_sort_fields, :occurred_at)
    sort_dir = validate_sort_dir(opts[:sort_dir])

    ordered_query =
      base_query
      |> order_by_action(sort_field, sort_dir)

    page_query(
      base_query,
      ordered_query,
      opts,
      fn rows -> Enum.map(rows, &Action.from_schema/1) end
    )
  end

  @doc "Toggles the is_retained flag for a scoped audit action."
  @spec toggle_retained(Scope.t(), pos_integer()) :: {:ok, Action.t()} | {:error, :not_found}
  def toggle_retained(%Scope{} = scope, action_id) when is_integer(action_id) do
    query =
      from(a in Tenancy.scope_query(ActionSchema, scope),
        where: a.id == ^action_id
      )

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      %ActionSchema{} = action ->
        action
        |> Ecto.Changeset.change(is_retained: not action.is_retained)
        |> Repo.update()
        |> map_action()
    end
  end

  defp page_query(count_query, ordered_query, opts, mapper) do
    page = max(opts[:page] || 1, 1)
    page_size = max(opts[:page_size] || @default_page_size, 1)
    total_entries = Repo.aggregate(count_query, :count, :id)

    entries =
      ordered_query
      |> offset(^((page - 1) * page_size))
      |> limit(^page_size)
      |> Repo.all()
      |> mapper.()

    %Page{
      entries: entries,
      page: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: ceil_div(total_entries, page_size)
    }
  end

  defp ceil_div(0, _), do: 0
  defp ceil_div(num, den), do: div(num + den - 1, den)

  defp validate_sort_field(field, allowed, default) do
    if field in allowed, do: field, else: default
  end

  defp validate_sort_dir(:asc), do: :asc
  defp validate_sort_dir(:desc), do: :desc
  defp validate_sort_dir("asc"), do: :asc
  defp validate_sort_dir("desc"), do: :desc
  defp validate_sort_dir(_), do: :desc

  defp order_by_mutation(query, :occurred_at, :asc),
    do: from(m in query, order_by: [asc: m.occurred_at, asc: m.id])

  defp order_by_mutation(query, :occurred_at, :desc),
    do: from(m in query, order_by: [desc: m.occurred_at, desc: m.id])

  defp order_by_mutation(query, field, :asc),
    do: from(m in query, order_by: [{:asc, field(m, ^field)}, {:asc, m.id}])

  defp order_by_mutation(query, field, :desc),
    do: from(m in query, order_by: [{:desc, field(m, ^field)}, {:desc, m.id}])

  defp order_by_action(query, :occurred_at, :asc),
    do: from(a in query, order_by: [asc: a.occurred_at, asc: a.id])

  defp order_by_action(query, :occurred_at, :desc),
    do: from(a in query, order_by: [desc: a.occurred_at, desc: a.id])

  defp order_by_action(query, field, :asc),
    do: from(a in query, order_by: [{:asc, field(a, ^field)}, {:asc, a.id}])

  defp order_by_action(query, field, :desc),
    do: from(a in query, order_by: [{:desc, field(a, ^field)}, {:desc, a.id}])

  defp maybe_search_mutations(query, nil), do: query
  defp maybe_search_mutations(query, ""), do: query

  defp maybe_search_mutations(query, search) do
    pattern = "%#{search}%"

    from(m in query,
      where:
        ilike(m.auditable_type, ^pattern) or
          ilike(m.event, ^pattern) or
          ilike(coalesce(m.subject_name, ""), ^pattern) or
          ilike(coalesce(m.subject_identifier, ""), ^pattern) or
          ilike(coalesce(m.auditable_id, ""), ^pattern) or
          ilike(coalesce(m.subject_id, ""), ^pattern) or
          ilike(coalesce(m.trace_id, ""), ^pattern) or
          ilike(coalesce(m.actor_role, ""), ^pattern) or
          ilike(m.actor_type, ^pattern)
    )
  end

  defp maybe_filter_mutation_event(query, nil), do: query
  defp maybe_filter_mutation_event(query, ""), do: query

  defp maybe_filter_mutation_event(query, event) when is_binary(event) do
    from(m in query, where: m.event == ^event)
  end

  defp maybe_search_actions(query, nil), do: query
  defp maybe_search_actions(query, ""), do: query

  defp maybe_search_actions(query, search) do
    pattern = "%#{search}%"

    from(a in query,
      where:
        ilike(a.event, ^pattern) or
          ilike(coalesce(a.actor_role, ""), ^pattern) or
          ilike(coalesce(a.url, ""), ^pattern) or
          ilike(coalesce(a.trace_id, ""), ^pattern) or
          ilike(a.actor_type, ^pattern) or
          fragment("?::text ILIKE ?", a.payload, ^pattern)
    )
  end

  defp maybe_filter_action_actor_type(query, nil), do: query
  defp maybe_filter_action_actor_type(query, ""), do: query

  defp maybe_filter_action_actor_type(query, actor_type) when is_binary(actor_type) do
    from(a in query, where: a.actor_type == ^actor_type)
  end

  defp maybe_filter_action_family(query, nil), do: query
  defp maybe_filter_action_family(query, ""), do: query

  defp maybe_filter_action_family(query, "http"),
    do: from(a in query, where: a.event == "http.request")

  defp maybe_filter_action_family(query, "auth"),
    do: from(a in query, where: like(a.event, "auth.%"))

  defp maybe_filter_action_family(query, "console"),
    do: from(a in query, where: a.event == "console.command")

  defp maybe_filter_action_family(query, "queue"),
    do: from(a in query, where: like(a.event, "queue.job.%"))

  defp maybe_filter_action_family(query, "domain"),
    do: from(a in query, where: like(a.event, "domain.%"))

  defp maybe_filter_action_family(query, _), do: query

  defp maybe_filter_action_result(query, nil), do: query
  defp maybe_filter_action_result(query, ""), do: query

  defp maybe_filter_action_result(query, "retained"),
    do: from(a in query, where: a.is_retained == true)

  defp maybe_filter_action_result(query, "failure") do
    from(a in query,
      where:
        a.event in ["auth.login.failed", "queue.job.failed"] or
          (a.event == "http.request" and
             fragment("coalesce(nullif(?->>'status', '')::int, 0) >= 400", a.payload)) or
          (a.event == "console.command" and
             fragment("coalesce(nullif(?->>'exit_code', '')::int, 0) != 0", a.payload)) or
          fragment("?::text ILIKE '%failed%'", a.payload)
    )
  end

  defp maybe_filter_action_result(query, _), do: query

  defp maybe_filter_action_diagnostics(query, "show"), do: query

  defp maybe_filter_action_diagnostics(query, _) do
    from(a in query,
      where:
        a.event != "http.request" or
          fragment("coalesce(nullif(?->>'status', '')::int, 0) >= 400", a.payload) or
          (not ilike(coalesce(a.url, ""), "%/livewire%") and
             not ilike(coalesce(a.url, ""), "%/api/ai/chat/turns/%") and
             not ilike(coalesce(a.url, ""), "%/media/assets/%") and
             not fragment("?::text ILIKE '%default-livewire.update%'", a.payload))
    )
  end

  defp persist_mutation(attributes, tenant_id) do
    attributes
    |> MutationSchema.changeset(tenant_id)
    |> Repo.insert()
    |> map_mutation()
  end

  defp persist_action(attributes, tenant_id) do
    attributes
    |> ActionSchema.changeset(tenant_id)
    |> Repo.insert()
    |> map_action()
  end

  defp map_mutation({:ok, mutation}), do: {:ok, Mutation.from_schema(mutation)}
  defp map_mutation({:error, changeset}), do: {:error, changeset}

  defp map_action({:ok, action}), do: {:ok, Action.from_schema(action)}
  defp map_action({:error, changeset}), do: {:error, changeset}
end
