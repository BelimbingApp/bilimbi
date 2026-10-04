defmodule Bilimbi.Base.Dashboard.Widget do
  @moduledoc """
  A validated dashboard entry contributed by an installed module.

  An entry is plain, immutable data validated at boot. It says where the entry
  sits (`placement`), what it is called, which capability the viewer needs, how
  often it refreshes, and which embeddable panel draws it (`embed`). The panel
  is a LiveComponent its owner declares in `priv/web_routes.exs`; the dashboard
  renders it with `<.discovered_panel>` and never names the owner's module
  (ADR 0006 embeddable panels, ADR 0009).

  `docs/README.md` in this package states what a panel receives.
  """

  @typedoc "A validated dashboard entry."
  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          embed: String.t(),
          placement: :grid | :section,
          size: :small | :medium | :large,
          order: non_neg_integer(),
          capability: String.t() | nil,
          refresh_interval: non_neg_integer()
        }

  defstruct [
    :id,
    :label,
    :embed,
    placement: :grid,
    size: :small,
    order: 0,
    capability: nil,
    refresh_interval: 0
  ]

  @doc false
  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    %__MODULE__{
      id: validate_id!(attrs[:id]),
      label: validate_label!(attrs[:label]),
      embed: validate_embed!(attrs[:embed]),
      placement: validate_placement(attrs[:placement]),
      size: validate_size(attrs[:size]),
      order: validate_order(attrs[:order]),
      capability: validate_capability(attrs[:capability]),
      refresh_interval: validate_refresh_interval(attrs[:refresh_interval])
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

  defp validate_embed!(embed) when is_binary(embed) and embed != "", do: embed

  defp validate_embed!(embed),
    do:
      raise(
        ArgumentError,
        "widget embed must name the panel that renders it, got: #{inspect(embed)}"
      )

  defp validate_placement(nil), do: :grid
  defp validate_placement(placement) when placement in [:grid, :section], do: placement

  defp validate_placement(placement),
    do:
      raise(
        ArgumentError,
        "widget placement must be :grid or :section, got: #{inspect(placement)}"
      )

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

  defp validate_capability(nil), do: nil
  defp validate_capability(capability) when is_binary(capability), do: capability

  defp validate_capability(capability),
    do:
      raise(
        ArgumentError,
        "widget capability must be a string or nil, got: #{inspect(capability)}"
      )

  defp validate_refresh_interval(nil), do: 0

  defp validate_refresh_interval(interval) when is_integer(interval) and interval >= 0,
    do: interval

  defp validate_refresh_interval(interval),
    do:
      raise(
        ArgumentError,
        "widget refresh_interval must be a non-negative integer of milliseconds, " <>
          "got: #{inspect(interval)}"
      )
end
