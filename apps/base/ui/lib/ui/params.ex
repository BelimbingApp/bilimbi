defmodule Bilimbi.Base.UI.Params do
  @moduledoc """
  Coercion of one untrusted param into a positive integer, an id, or a blank.

  LiveViews used to keep a private `to_int`, `positive_integer`, `parse_id`,
  or `nilify` for this. Those copies disagreed about trimming and about
  whether a bad id was `nil` or `:error`. This module is that coercion.

  `positive_integer/2` trims, accepts only a positive integer, and otherwise
  returns the given default (which may itself be `nil` or `0`). `positive_id/1`
  is the `{:ok, id} | :error` shape a `with` chain wants. `blank_to_nil/1`
  turns `nil` and `""` into `nil` and leaves every other value, including
  whitespace, alone. `trimmed/1` is the trim those integer parsers share.

  Call them by module. They are not imported from `Bilimbi.Base.UI`'s HTML
  helpers: other LiveViews still define a private function of the same name,
  and an import would stop those modules compiling. Delete the private copy
  and call this module. A value that is allowed to be zero or negative, such
  as an audit payload status, is not this coercion.
  """

  @type positive_id :: {:ok, pos_integer()} | :error

  @doc """
  A positive integer parsed from `value`, or `default` when `value` is not one.

  Binaries are trimmed first. `0`, negatives, and partial parses (`"25abc"`,
  `"1.5"`) are not positive integers.
  """
  @spec positive_integer(term(), term()) :: term()
  def positive_integer(value, default \\ nil)

  def positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  def positive_integer(value, default) when is_binary(value) do
    case Integer.parse(trimmed(value)) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  def positive_integer(_value, default), do: default

  @doc """
  `{:ok, id}` when `value` is a positive integer, `:error` otherwise.

  Binaries are trimmed first. This is the shape a `with` chain wants; a
  caller that needs `nil` on failure uses `positive_integer/2`.
  """
  @spec positive_id(term()) :: positive_id()
  def positive_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  def positive_id(value) when is_binary(value) do
    case positive_integer(value) do
      nil -> :error
      id -> {:ok, id}
    end
  end

  def positive_id(_value), do: :error

  @doc """
  `nil` for `nil` and `""`. Every other value is returned unchanged.
  """
  @spec blank_to_nil(term()) :: term()
  def blank_to_nil(value) when value in [nil, ""], do: nil
  def blank_to_nil(value), do: value

  @doc """
  `String.trim/1` for a binary. Any other term is returned unchanged.
  """
  @spec trimmed(term()) :: term()
  def trimmed(value) when is_binary(value), do: String.trim(value)
  def trimmed(value), do: value
end
