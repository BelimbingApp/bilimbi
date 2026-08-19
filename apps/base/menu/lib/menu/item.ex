defmodule Bilimbi.Base.Menu.Item do
  @moduledoc """
  One navigation entry contributed by an installed module.

  Mirrors Belimbing's `Config/menu.php` item shape — `id`, `label`, `icon`,
  `route`, `permission`, `parent` — so the tree is portable between the two
  products. `capability` is the Bilimbi name for Belimbing's `permission`.
  `source` records the contributing module descriptor id (e.g. `core/user`).
  """

  @enforce_keys [:id, :label]
  defstruct [:id, :label, :icon, :route, :capability, :parent, :source, order: 0]

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          icon: String.t() | nil,
          route: String.t() | nil,
          capability: String.t() | nil,
          parent: String.t() | nil,
          source: String.t() | nil,
          order: integer()
        }

  @id_pattern ~r/^[a-z0-9][a-z0-9._-]*$/

  @doc """
  Builds an item from a plain map, raising on an invalid shape.

  Contributions cross a module boundary as plain terms, so the shape is
  validated here rather than trusted. An optional `source` (module descriptor id)
  may be provided to record the contributing module.
  """
  @spec new!(map(), String.t() | nil) :: t()
  def new!(attrs, source \\ nil) when is_map(attrs) do
    item = struct!(__MODULE__, attrs)
    item = if is_binary(source) and is_nil(item.source), do: %{item | source: source}, else: item

    validate_id!(item.id, "id")
    if item.parent, do: validate_id!(item.parent, "parent")

    unless is_binary(item.label) and item.label != "" do
      raise ArgumentError, "menu item #{item.id} needs a non-empty label"
    end

    unless is_nil(item.capability) or is_binary(item.capability) do
      raise ArgumentError, "menu item #{item.id} capability must be a string or nil"
    end

    unless is_nil(item.route) or is_binary(item.route) do
      raise ArgumentError, "menu item #{item.id} route must be a string or nil"
    end

    unless is_nil(item.source) or is_binary(item.source) do
      raise ArgumentError, "menu item #{item.id} source must be a string or nil"
    end

    unless is_integer(item.order) do
      raise ArgumentError, "menu item #{item.id} order must be an integer"
    end

    if item.parent == item.id do
      raise ArgumentError, "menu item #{item.id} cannot be its own parent"
    end

    item
  end

  @doc "True when the item only groups children and navigates nowhere itself."
  @spec container?(t()) :: boolean()
  def container?(%__MODULE__{route: nil}), do: true
  def container?(%__MODULE__{}), do: false

  defp validate_id!(value, field) do
    unless is_binary(value) and Regex.match?(@id_pattern, value) do
      raise ArgumentError, "menu item #{field} is invalid: #{inspect(value)}"
    end
  end
end
