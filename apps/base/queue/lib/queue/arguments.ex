defmodule Bilimbi.Base.Queue.Arguments do
  @moduledoc false

  @max_depth 8
  @max_members 100
  @max_key_bytes 128
  @max_string_bytes 16_384
  @max_encoded_bytes 65_536

  @spec validate(term()) :: {:ok, map()} | {:error, :invalid_args}
  def validate(args) when is_map(args) and not is_struct(args) do
    with :ok <- validate_value(args, 0),
         {:ok, encoded} <- Jason.encode(args),
         true <- byte_size(encoded) <= @max_encoded_bytes do
      {:ok, args}
    else
      _error -> {:error, :invalid_args}
    end
  end

  def validate(_args), do: {:error, :invalid_args}

  defp validate_value(_value, depth) when depth > @max_depth, do: :error
  defp validate_value(value, _depth) when is_nil(value) or is_boolean(value), do: :ok
  defp validate_value(value, _depth) when is_integer(value), do: :ok

  defp validate_value(value, _depth) when is_float(value) do
    if finite_float?(value), do: :ok, else: :error
  end

  defp validate_value(value, _depth) when is_binary(value) do
    if byte_size(value) <= @max_string_bytes and String.valid?(value), do: :ok, else: :error
  end

  defp validate_value(value, depth) when is_list(value) do
    if bounded_proper_list?(value, @max_members) do
      validate_members(value, depth + 1)
    else
      :error
    end
  end

  defp validate_value(value, depth) when is_map(value) and not is_struct(value) do
    if map_size(value) <= @max_members do
      Enum.reduce_while(value, :ok, fn
        {key, member}, :ok
        when is_binary(key) and byte_size(key) <= @max_key_bytes ->
          if String.valid?(key) and validate_value(member, depth + 1) == :ok,
            do: {:cont, :ok},
            else: {:halt, :error}

        _entry, :ok ->
          {:halt, :error}
      end)
    else
      :error
    end
  end

  defp validate_value(_value, _depth), do: :error

  defp validate_members(values, depth) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      if validate_value(value, depth) == :ok, do: {:cont, :ok}, else: {:halt, :error}
    end)
  end

  defp bounded_proper_list?([], _remaining), do: true

  defp bounded_proper_list?([_head | tail], remaining) when remaining > 0,
    do: bounded_proper_list?(tail, remaining - 1)

  defp bounded_proper_list?(_value, _remaining), do: false

  defp finite_float?(value) do
    case :erlang.float_to_binary(value, [:compact]) do
      binary when binary in ["nan", "inf", "-inf"] -> false
      _binary -> true
    end
  rescue
    ArgumentError -> false
  end
end
