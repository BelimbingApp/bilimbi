defmodule Bilimbi.Base.Settings.JsonValue do
  @moduledoc false

  use Ecto.Type

  @impl true
  def type, do: :map

  @impl true
  def cast(value), do: if(json_value?(value), do: {:ok, value}, else: :error)

  @impl true
  def load(value), do: if(json_value?(value), do: {:ok, value}, else: :error)

  @impl true
  def dump(value), do: if(json_value?(value), do: {:ok, value}, else: :error)

  defp json_value?(value)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: true

  defp json_value?(value) when is_list(value), do: Enum.all?(value, &json_value?/1)

  defp json_value?(value) when is_map(value) do
    Enum.all?(value, fn {key, nested} -> is_binary(key) and json_value?(nested) end)
  end

  defp json_value?(_value), do: false
end
