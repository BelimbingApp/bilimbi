defmodule Bilimbi.Core.Geonames.Web.CamelList do
  @moduledoc """
  Geonames index pages keep `sortBy`, `sortDir`, and `perPage` in the URL.

  `Bilimbi.Base.UI.ListState` speaks `sort_by` and `sort_dir`. This bridge
  renames those keys. A forged page size still snaps up to the next allowed
  size, which is what these pages did before they used `ListState`.
  """

  alias Bilimbi.Base.UI.ListState
  alias Bilimbi.Base.UI.Params

  def parse(params, spec) when is_map(params) do
    ListState.parse(inbound(params, spec), spec)
  end

  def to_params(%ListState{} = state) do
    state
    |> ListState.to_params()
    |> Map.delete("sort_by")
    |> Map.delete("sort_dir")
    |> Map.put("sortBy", Atom.to_string(state.sort_by))
    |> Map.put("sortDir", Atom.to_string(state.sort_dir))
  end

  def apply_filters(%ListState{} = state, filters) when is_map(filters) do
    ListState.apply_filters(state, snap_posted_page_size(filters, state.spec))
  end

  def apply_filters(%ListState{} = state, filters), do: ListState.apply_filters(state, filters)

  defp inbound(params, spec) do
    params
    |> Map.put("sort_by", params["sortBy"])
    |> Map.put("sort_dir", params["sortDir"])
    |> snap_posted_page_size(spec)
  end

  defp snap_posted_page_size(params, spec) do
    case Map.fetch(params, "perPage") do
      {:ok, value} -> Map.put(params, "perPage", snap_page_size(value, spec))
      :error -> params
    end
  end

  defp snap_page_size(value, spec) do
    parsed = Params.positive_integer(value, hd(spec.page_sizes))
    snapped = Enum.find(spec.page_sizes, List.last(spec.page_sizes), &(&1 >= parsed))
    to_string(snapped)
  end
end
