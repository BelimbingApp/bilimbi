defmodule Bilimbi.Base.Workflow.JSON do
  @moduledoc false
  # Source json fields may be objects, arrays or scalars. :map rejects source
  # arrays; this type preserves their decoded shape without PHP deserialization.
  use Ecto.Type

  def type, do: :map
  def cast(value), do: validate(value)
  def load(value), do: {:ok, value}
  def dump(value), do: validate(value)

  defp validate(value) do
    if json?(value), do: {:ok, value}, else: :error
  end

  defp json?(value)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: true

  defp json?(value) when is_list(value), do: Enum.all?(value, &json?/1)

  defp json?(value) when is_map(value) and not is_struct(value),
    do: Enum.all?(value, fn {key, item} -> is_binary(key) and json?(item) end)

  defp json?(_value), do: false
end
