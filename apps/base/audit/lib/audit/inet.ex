defmodule Bilimbi.Base.Audit.Inet do
  @moduledoc false

  use Ecto.Type

  @impl Ecto.Type
  def type, do: :inet

  @impl Ecto.Type
  def cast(%Postgrex.INET{} = inet), do: {:ok, inet}

  def cast(address) when is_tuple(address) and tuple_size(address) in [4, 8] do
    {:ok, %Postgrex.INET{address: address}}
  end

  def cast(address) when is_binary(address) do
    case :inet.parse_address(String.to_charlist(address)) do
      {:ok, parsed} -> {:ok, %Postgrex.INET{address: parsed}}
      {:error, :einval} -> :error
    end
  end

  def cast(_value), do: :error

  @impl Ecto.Type
  def load(%Postgrex.INET{} = inet), do: {:ok, inet}
  def load(_value), do: :error

  @impl Ecto.Type
  def dump(%Postgrex.INET{} = inet), do: {:ok, inet}
  def dump(_value), do: :error
end
