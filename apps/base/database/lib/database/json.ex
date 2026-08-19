defmodule Bilimbi.Base.Database.Json do
  @moduledoc """
  Ecto type for compatible PostgreSQL JSON values that may be objects or arrays.

  Ecto's built-in `:map` field rejects JSON arrays even though Laravel commonly
  stores array-shaped values in `json` columns.
  """

  use Ecto.Type

  @impl Ecto.Type
  def type, do: :map

  @impl Ecto.Type
  def cast(value) when is_map(value) or is_list(value), do: {:ok, value}

  def cast(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) or is_list(decoded) -> {:ok, decoded}
      _ -> :error
    end
  end

  def cast(_value), do: :error

  @impl Ecto.Type
  def load(value) when is_map(value) or is_list(value), do: {:ok, value}

  def load(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) or is_list(decoded) -> {:ok, decoded}
      _ -> :error
    end
  end

  def load(_value), do: :error

  @impl Ecto.Type
  def dump(value) when is_map(value) or is_list(value), do: {:ok, value}
  def dump(_value), do: :error
end
