defmodule Bilimbi.Base.AgentApi do
  @moduledoc """
  The operations installed modules register for agents, found by search and
  called as a person (ADR 0021).

  An agent's loop is search, then describe, then call. `search/3` ranks the
  operations and guides the scope's person may use by the words given.
  `describe/2` returns one operation's input and output schemas and its
  related guides. `call/3` runs it through `Bilimbi.Base.AgentApi.Dispatcher`,
  which asks the same capability the screen asks before the module's own
  facade does the work.

  Modules register through their `:agent_api` contribution;
  `Bilimbi.Base.AgentApi.ContributionValidator` owns that contract. A module
  that is not installed contributes nothing, so its operations are not
  found and not called.

  Only read operations run. A write answers `{:error, :writes_not_enabled}`
  until connections carry a level and drafts exist to approve.
  """

  alias Bilimbi.Base.AgentApi.Definition
  alias Bilimbi.Base.AgentApi.Dispatcher
  alias Bilimbi.Base.AgentApi.Guide
  alias Bilimbi.Base.AgentApi.Reach
  alias Bilimbi.Base.AgentApi.Search
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Tenancy.Scope

  @default_limit 10
  @max_limit 50

  @type disposition :: :call | {:refused, :writes_not_enabled}

  @type result :: %{
          type: :operation | :guide,
          key: String.t(),
          title: String.t(),
          summary: String.t(),
          kind: Definition.kind() | nil,
          available: boolean(),
          disposition: disposition() | nil,
          reason: :missing_capability | nil
        }

  @doc """
  The operations and guides the scope's person may use, ranked by `words`
  (see `Bilimbi.Base.AgentApi.Search`).

  Options:

    * `:kind` — `:read` or `:write`, to keep operations of one kind; guides
      are then left out;
    * `:limit` — at most this many results, default #{@default_limit}, at
      most #{@max_limit};
    * `:include_unavailable` — also return what the person may not use,
      marked `available: false` with `reason: :missing_capability`, so the
      agent can tell the person what to ask for.

  Each result names its `type`, `key`, `title`, `summary` and, for an
  operation, its `kind` and its `disposition`: `:call` for a read, and
  `{:refused, :writes_not_enabled}` for a write.
  """
  @spec search(Scope.t(), String.t(), keyword()) :: [result()]
  def search(%Scope{} = scope, words, opts \\ []) when is_binary(words) and is_list(opts) do
    registry = registry!()
    reach = Reach.capabilities(scope)
    include_unavailable? = Keyword.get(opts, :include_unavailable, false)
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_limit) |> max(1)

    (Map.values(registry.operations) ++ Map.values(registry.guides))
    |> filter_kind(Keyword.get(opts, :kind))
    |> Enum.filter(&(include_unavailable? or MapSet.member?(reach, &1.capability)))
    |> Search.rank(words)
    |> Enum.take(limit)
    |> Enum.map(fn {entry, _score} -> result(entry, reach) end)
  end

  @doc """
  One operation as an agent needs it before calling: its schemas, its
  capability, how it would run for this scope, and its related guides.
  """
  @spec describe(Scope.t(), String.t()) ::
          {:ok, map()} | {:error, :unknown_operation | {:forbidden, :missing_capability}}
  def describe(%Scope{} = scope, key) when is_binary(key) do
    registry = registry!()
    reach = Reach.capabilities(scope)

    with {:ok, operation} <- fetch(registry.operations, key, :unknown_operation),
         :ok <- reachable(operation, reach) do
      {:ok,
       %{
         key: operation.key,
         title: operation.title,
         summary: operation.summary,
         kind: operation.kind,
         capability: operation.capability,
         approval: operation.approval,
         disposition: disposition(operation),
         input: operation.input,
         output: operation.output,
         guides:
           registry
           |> related_guides(operation.key, reach)
           |> Enum.map(&%{key: &1.key, title: &1.title})
       }}
    end
  end

  @doc "One guide's text, for a scope that holds its capability."
  @spec guide(Scope.t(), String.t()) ::
          {:ok, map()} | {:error, :unknown_guide | {:forbidden, :missing_capability}}
  def guide(%Scope{} = scope, key) when is_binary(key) do
    with {:ok, guide} <- fetch(registry!().guides, key, :unknown_guide),
         :ok <- reachable(guide, Reach.capabilities(scope)) do
      {:ok, %{key: guide.key, title: guide.title, summary: guide.summary, body: guide.body}}
    end
  end

  @doc """
  Runs one operation as the scope's person, checking what the screen
  checks; see `Bilimbi.Base.AgentApi.Dispatcher` for the steps.

  `input` is the decoded JSON object, keyed by strings. A success is
  `{:ok, %{"result" => result, "meta" => meta}}`, JSON-ready: a field the
  person may not see reads `%{"restricted" => true}`, and a list operation's
  `meta` carries its `"page"`. The errors are `:unknown_operation`,
  `{:invalid_input, %{field => [message]}}`, `{:forbidden, reason}`,
  `:writes_not_enabled`, `:not_found` and `{:rejected, reason}`.
  """
  @spec call(Scope.t(), String.t(), map()) :: {:ok, map()} | {:error, Dispatcher.error()}
  def call(%Scope{} = scope, key, input) when is_binary(key) do
    registry!().operations
    |> Map.get(key)
    |> Dispatcher.call(scope, input)
  end

  defp registry!, do: ContributionRegistry.consumer!(:agent_api)

  defp filter_kind(entries, nil), do: entries

  defp filter_kind(entries, kind) when kind in [:read, :write],
    do: Enum.filter(entries, &match?(%Definition{kind: ^kind}, &1))

  defp fetch(map, key, error) do
    case Map.fetch(map, key) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, error}
    end
  end

  defp reachable(entry, reach) do
    if MapSet.member?(reach, entry.capability),
      do: :ok,
      else: {:error, {:forbidden, :missing_capability}}
  end

  defp related_guides(registry, key, reach) do
    registry.guides
    |> Map.values()
    |> Enum.filter(
      &(String.starts_with?(key, &1.key <> ".") and MapSet.member?(reach, &1.capability))
    )
    |> Enum.sort_by(& &1.key)
  end

  defp result(entry, reach) do
    available? = MapSet.member?(reach, entry.capability)

    %{
      type: type(entry),
      key: entry.key,
      title: entry.title,
      summary: entry.summary,
      kind: kind(entry),
      available: available?,
      disposition: if(available?, do: disposition(entry)),
      reason: if(available?, do: nil, else: :missing_capability)
    }
  end

  defp type(%Definition{}), do: :operation
  defp type(%Guide{}), do: :guide

  defp kind(%Definition{kind: kind}), do: kind
  defp kind(%Guide{}), do: nil

  defp disposition(%Definition{kind: :read}), do: :call
  defp disposition(%Definition{kind: :write}), do: {:refused, :writes_not_enabled}
  defp disposition(%Guide{}), do: nil
end
