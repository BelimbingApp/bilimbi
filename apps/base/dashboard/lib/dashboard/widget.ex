defmodule Bilimbi.Base.Dashboard.Widget do
  @moduledoc """
  A validated widget definition contributed by an installed module.

  Widgets are plain, immutable structs. The `component` field names a function
  component module that the dashboard LiveView renders in a grid cell. Widgets
  must not perform I/O or access process-local state during construction.
  """

  @typedoc "A validated widget definition."
  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          component: module() | nil,
          size: :small | :medium | :large,
          order: non_neg_integer(),
          capability: String.t() | nil
        }

  defstruct [:id, :label, component: nil, size: :small, order: 0, capability: nil]

  @doc false
  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    %__MODULE__{
      id: validate_id!(attrs[:id]),
      label: validate_label!(attrs[:label]),
      component: attrs[:component],
      size: validate_size(attrs[:size]),
      order: validate_order(attrs[:order]),
      capability: attrs[:capability]
    }
  end

  defp validate_id!(nil), do: raise(ArgumentError, "widget id is required")
  defp validate_id!(id) when is_binary(id), do: id
  defp validate_id!(id), do: raise(ArgumentError, "widget id must be a string, got: #{inspect(id)}")

  defp validate_label!(nil), do: raise(ArgumentError, "widget label is required")
  defp validate_label!(""), do: raise(ArgumentError, "widget label must not be empty")
  defp validate_label!(label) when is_binary(label), do: label
  defp validate_label!(label), do: raise(ArgumentError, "widget label must be a string, got: #{inspect(label)}")

  defp validate_size(nil), do: :small
  defp validate_size(size) when size in [:small, :medium, :large], do: size
  defp validate_size(size), do: raise(ArgumentError, "widget size must be :small, :medium, or :large, got: #{inspect(size)}")

  defp validate_order(nil), do: 0
  defp validate_order(order) when is_integer(order) and order >= 0, do: order
  defp validate_order(order), do: raise(ArgumentError, "widget order must be a non-negative integer, got: #{inspect(order)}")
end
