defmodule Bilimbi.Base.Media.ULID do
  @moduledoc false
  @alphabet ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"

  def generate do
    value =
      :binary.decode_unsigned(
        <<System.system_time(:millisecond)::48, :crypto.strong_rand_bytes(10)::binary>>
      )

    value
    |> Integer.digits(32)
    |> Enum.map(&Enum.at(@alphabet, &1))
    |> List.to_string()
    |> String.pad_leading(26, "0")
  end
end
