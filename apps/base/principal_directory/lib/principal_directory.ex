defmodule Bilimbi.Base.PrincipalDirectory do
  @moduledoc """
  Names and ranks the principals a Base screen already references.

  Base owns grants, sessions and assignments; Core owns the people behind them.
  This is the seam, specified in `docs/architecture/decisions/0011-principal-directory-seam.md`.

  ## The consumer names its candidates first

  This module is never asked for "every principal in the tenant". A consumer
  selects the distinct `{kind, id}` pairs its already-filtered query references,
  **before** pagination, and passes exactly those. A screen showing six
  principals resolves six, whatever the tenant's size.

  It returns them ordered by display name, which the consumer feeds to
  `array_position/2` so the database orders before `offset`/`limit`. Ordering a
  page that some other clause already selected is not a sort, and it is the
  defect that sank the first attempt at this (#439).

  ## Identity is a pair, never an id

  `principal_capabilities` stores users and agents in one table, so a user 5 and
  an agent 5 are different principals. Everything here is keyed on
  `{kind, id}`. Ties break on normalised name, then kind, then id, so two people
  with the same display name land in the same order on every page and every run.

  ## Failure is visible, never silent

  - Over the ceiling: `{:error, :too_many_candidates}`. The consumer keeps its
    rows and shows durable type and id.
  - A name **search** with no provider for some candidate kind:
    `{:error, :name_search_unavailable}`. Search does not degrade — one that
    silently matches nothing and one that silently matches everything are both
    lies about the question asked.

  A principal the provider cannot see is simply absent from the result. It is
  not an error, and the consumer must keep its row: a grant to a deleted
  principal is exactly what an operator needs to see.
  """

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.PrincipalDirectory.Provider
  alias Bilimbi.Base.Tenancy.Scope

  @typedoc "A principal a consumer's query references."
  @type candidate :: {Provider.kind(), pos_integer()}

  @typedoc "A resolved principal, named as the operator should see it."
  @type named :: %{kind: Provider.kind(), id: pos_integer(), name: String.t()}

  @default_ceiling 2_000

  @doc """
  Resolves and ranks `candidates` within `scope`.

  Options:

    * `:search` — case-insensitive substring on the display name. Absent means
      no filtering; present with an unresolvable kind is an error, not a
      degraded result.
    * `:ceiling` — maximum candidates to resolve, default `#{@default_ceiling}`.
    * `:providers` — the provider map to use instead of the installed one. The
      contract test supplies a double this way, because Base cannot exercise a
      Core implementation. A caller that has already resolved the providers may
      pass them to avoid a second registry read.

  """
  @spec rank(Scope.t(), [candidate()], keyword()) ::
          {:ok, [named()]} | {:error, :too_many_candidates | :name_search_unavailable}
  def rank(%Scope{} = scope, candidates, opts \\ []) when is_list(candidates) do
    candidates = Enum.uniq(candidates)
    ceiling = Keyword.get(opts, :ceiling, @default_ceiling)
    search = normalise_search(Keyword.get(opts, :search))

    providers = Keyword.get_lazy(opts, :providers, &providers/0)
    kinds = candidates |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    cond do
      length(candidates) > ceiling ->
        {:error, :too_many_candidates}

      search != nil and Enum.any?(kinds, &(not Map.has_key?(providers, &1))) ->
        {:error, :name_search_unavailable}

      true ->
        {:ok, candidates |> resolve(scope, providers) |> filter(search) |> order()}
    end
  end

  @doc "The installed provider modules, keyed by the kind each answers for."
  @spec providers() :: %{Provider.kind() => module()}
  def providers, do: ContributionRegistry.consumer!(:principal_directory)

  defp resolve(candidates, scope, providers) do
    candidates
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {kind, ids} ->
      case Map.fetch(providers, kind) do
        {:ok, provider} ->
          names = provider.names(scope, ids)

          for id <- ids, name = Map.get(names, id), is_binary(name) and name != "" do
            %{kind: kind, id: id, name: name}
          end

        :error ->
          []
      end
    end)
  end

  defp filter(named, nil), do: named

  defp filter(named, search) do
    Enum.filter(named, &String.contains?(String.downcase(&1.name), search))
  end

  # Normalised name first so the order matches what the operator reads; kind and
  # id only to make ties deterministic. Sorting on the raw binary would file
  # every lowercase initial after every uppercase one -- "eMart" below "Zulu" --
  # and an order the reader cannot see reads as no order at all.
  defp order(named) do
    Enum.sort_by(named, &{String.downcase(&1.name), &1.kind, &1.id})
  end

  defp normalise_search(nil), do: nil

  defp normalise_search(term) when is_binary(term) do
    case term |> String.trim() |> String.downcase() do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
