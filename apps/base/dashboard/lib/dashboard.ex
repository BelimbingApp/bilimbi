defmodule Bilimbi.Base.Dashboard do
  @moduledoc """
  Public API for the dashboard installed modules contribute to.

  A module declares its dashboard entries through its contribution provider
  and draws each one with an embeddable panel it owns. This module owns
  validation and ordering of the catalogue; it owns no tables.

  The arrangement each account chose (which entries, in what order) is stored
  in the `ui.dashboard.layout` and `ui.dashboard.sections` settings. The
  catalogue comes from here; `Bilimbi.Base.Dashboard.Web.IndexLive` applies
  the arrangement and renders the page at `/dashboard`.
  """

  alias Bilimbi.Base.Dashboard.Widget
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  @typedoc "A validated dashboard entry contributed by an installed module."
  @type t :: %Widget{}

  @doc "Every validated entry of either placement, ordered, from all installed modules."
  @spec entries() :: [t()]
  def entries, do: ContributionRegistry.consumer!(:dashboard)

  @doc "The grid widgets, ordered."
  @spec widgets() :: [t()]
  def widgets, do: Enum.filter(entries(), &(&1.placement == :grid))

  @doc "The full-width sections below the grid, ordered."
  @spec sections() :: [t()]
  def sections, do: Enum.filter(entries(), &(&1.placement == :section))

  @doc """
  Looks up a validated grid widget by its contribution id.
  """
  @spec fetch_widget(String.t()) :: {:ok, t()} | :error
  def fetch_widget(id) when is_binary(id) do
    case Enum.find(widgets(), &(&1.id == id)) do
      nil -> :error
      widget -> {:ok, widget}
    end
  end
end
