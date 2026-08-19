defmodule Bilimbi.Base.Dashboard.Widget do
  @moduledoc """
  A validated widget definition contributed by an installed module.

  Widgets are plain, immutable structs validated at boot time. The catalogue
  determines which widgets appear and in what order. Rendering is owned by the
  dashboard LiveView adapter; future widget renderer modules may implement the
  `Bilimbi.Base.Dashboard.Widget` behaviour to receive their own assign set.
  """

  @typedoc "A validated widget definition."
  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          size: :small | :medium | :large,
          order: non_neg_integer(),
          capability: String.t() | nil
        }

  defstruct [:id, :label, size: :small, order: 0, capability: nil]

  @doc "Display title for this widget."
  @callback widget_title() :: String.t()

  @doc "Grid size hint for this widget."
  @callback widget_size() :: :small | :medium | :large

  @doc """
  Refresh interval in milliseconds. Return 0 to disable auto-refresh.
  The dashboard LiveView will schedule a `handle_info(:refresh_widget, ...)`
  message at this interval.
  """
  @callback widget_refresh_interval() :: non_neg_integer()

  @doc "The assign keys this widget needs from the dashboard LiveView."
  @callback widget_assigns() :: [atom()]

  @doc false
  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    %__MODULE__{
      id: validate_id!(attrs[:id]),
      label: validate_label!(attrs[:label]),
      size: validate_size(attrs[:size]),
      order: validate_order(attrs[:order]),
      capability: attrs[:capability]
    }
  end

  defp validate_id!(nil), do: raise(ArgumentError, "widget id is required")
  defp validate_id!(id) when is_binary(id), do: id

  defp validate_id!(id),
    do: raise(ArgumentError, "widget id must be a string, got: #{inspect(id)}")

  defp validate_label!(nil), do: raise(ArgumentError, "widget label is required")
  defp validate_label!(""), do: raise(ArgumentError, "widget label must not be empty")
  defp validate_label!(label) when is_binary(label), do: label

  defp validate_label!(label),
    do: raise(ArgumentError, "widget label must be a string, got: #{inspect(label)}")

  defp validate_size(nil), do: :small
  defp validate_size(size) when size in [:small, :medium, :large], do: size

  defp validate_size(size),
    do:
      raise(
        ArgumentError,
        "widget size must be :small, :medium, or :large, got: #{inspect(size)}"
      )

  defp validate_order(nil), do: 0
  defp validate_order(order) when is_integer(order) and order >= 0, do: order

  defp validate_order(order),
    do:
      raise(ArgumentError, "widget order must be a non-negative integer, got: #{inspect(order)}")
end
