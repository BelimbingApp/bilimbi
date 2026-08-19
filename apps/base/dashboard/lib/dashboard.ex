defmodule Bilimbi.Base.Dashboard do
  @moduledoc """
  Public API for the widget-based dashboard contributed by installed modules.

  Dashboard widgets are declared by their owning module through the contribution
  provider. This module owns validation and ordering; it owns no tables and
  performs no I/O.

  The widget layout (order and visibility per user) is stored in the
  `ui.dashboard.layout` setting. This module provides the widget catalogue;
  the LiveView adapter applies the layout.
  """

  alias Bilimbi.Base.Dashboard.Widget
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  @typedoc "A validated widget definition contributed by an installed module."
  @type t :: %Widget{}

  @doc "Every validated widget, ordered, from all installed modules."
  @spec widgets() :: [t()]
  def widgets, do: ContributionRegistry.consumer!(:dashboard)

  @doc """
  Looks up a validated widget by its contribution id.
  """
  @spec fetch_widget(String.t()) :: {:ok, t()} | :error
  def fetch_widget(id) when is_binary(id) do
    case Enum.find(widgets(), &(&1.id == id)) do
      nil -> :error
      widget -> {:ok, widget}
    end
  end
end
