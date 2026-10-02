defmodule Bilimbi.Base.Menu.Capability do
  @moduledoc """
  Capability requirements shared by navigation and route guards.

  A string requires that capability. `{:any_of, keys}` requires at least one
  of a non-empty list of distinct, non-blank capability strings. `nil` leaves
  capability gating to the caller's authentication boundary. Each section and
  operation within a combined page must still enforce its own capability.
  """

  @type t :: String.t() | {:any_of, [String.t()]} | nil

  @doc "Whether a declaration has a supported shape."
  @spec valid?(term()) :: boolean()
  def valid?(nil), do: true
  def valid?(key) when is_binary(key), do: true

  def valid?({:any_of, keys}) when is_list(keys) and keys != [] do
    Enum.all?(keys, &(is_binary(&1) and String.trim(&1) != "")) and
      length(Enum.uniq(keys)) == length(keys)
  end

  def valid?(_), do: false

  @doc "Evaluates a requirement through the caller's single-capability decision."
  @spec allowed?(t(), (String.t() -> boolean())) :: boolean()
  def allowed?(nil, _allowed?), do: true
  def allowed?(key, allowed?) when is_binary(key), do: allowed?.(key)

  def allowed?({:any_of, keys} = requirement, allowed?) do
    valid?(requirement) and Enum.any?(keys, allowed?)
  end

  def allowed?(_, _allowed?), do: false

  @doc "The individual capability keys in a requirement."
  @spec keys(t()) :: [String.t()]
  def keys(nil), do: []
  def keys(key) when is_binary(key), do: [key]
  def keys({:any_of, keys}), do: keys

  @doc "A readable label for diagnostics and search."
  @spec label(t()) :: String.t() | nil
  def label(nil), do: nil
  def label(key) when is_binary(key), do: key
  def label({:any_of, keys}), do: Enum.join(keys, " or ")
end
