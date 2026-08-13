defmodule Bilimbi.Base.Settings.Encryption do
  @moduledoc """
  Laravel-compatible AES-256-CBC envelope for adopted encrypted setting rows.

  The key is read from `:bilimbi_base_settings, :belimbing_app_key`. Production
  may supply it through `BELIMBING_APP_KEY`; it is never logged or stored in a
  setting row. Unencrypted settings do not require the key.
  """

  @iv_bytes 16
  @block_bytes 16

  @spec encrypt!(term()) :: String.t()
  def encrypt!(value) do
    key = key!()
    iv = :crypto.strong_rand_bytes(@iv_bytes)
    plaintext = value |> Jason.encode!() |> pad()
    ciphertext = :crypto.crypto_one_time(:aes_256_cbc, key, iv, plaintext, true)
    encoded_iv = Base.encode64(iv)
    encoded_value = Base.encode64(ciphertext)

    mac =
      :crypto.mac(:hmac, :sha256, key, encoded_iv <> encoded_value) |> Base.encode16(case: :lower)

    %{"iv" => encoded_iv, "value" => encoded_value, "mac" => mac, "tag" => ""}
    |> Jason.encode!()
    |> Base.encode64()
  end

  @spec decrypt!(String.t()) :: term()
  def decrypt!(envelope) when is_binary(envelope) do
    key = key!()

    with {:ok, payload_json} <- Base.decode64(envelope),
         {:ok, %{"iv" => encoded_iv, "value" => encoded_value, "mac" => encoded_mac}} <-
           Jason.decode(payload_json),
         {:ok, iv} <- Base.decode64(encoded_iv),
         true <- byte_size(iv) == @iv_bytes,
         {:ok, ciphertext} <- Base.decode64(encoded_value),
         {:ok, supplied_mac} <- Base.decode16(encoded_mac, case: :mixed) do
      expected_mac = :crypto.mac(:hmac, :sha256, key, encoded_iv <> encoded_value)

      unless :crypto.hash_equals(expected_mac, supplied_mac) do
        raise ArgumentError, "encrypted setting payload authentication failed"
      end

      ciphertext
      |> then(&:crypto.crypto_one_time(:aes_256_cbc, key, iv, &1, false))
      |> unpad!()
      |> Jason.decode!()
    else
      _invalid -> raise ArgumentError, "encrypted setting payload is malformed"
    end
  end

  def decrypt!(_envelope), do: raise(ArgumentError, "encrypted setting payload must be a string")

  defp key! do
    case Application.get_env(:bilimbi_base_settings, :belimbing_app_key) do
      "base64:" <> encoded -> decode_key!(encoded)
      _missing -> raise ArgumentError, "BELIMBING_APP_KEY is required for encrypted settings"
    end
  end

  defp decode_key!(encoded) do
    case Base.decode64(encoded) do
      {:ok, key} when byte_size(key) == 32 ->
        key

      _invalid ->
        raise ArgumentError, "BELIMBING_APP_KEY must contain a base64-encoded 32-byte key"
    end
  end

  defp pad(binary) do
    length = @block_bytes - rem(byte_size(binary), @block_bytes)
    binary <> :binary.copy(<<length>>, length)
  end

  defp unpad!(binary) do
    padding = :binary.last(binary)

    if padding in 1..@block_bytes and
         :binary.part(binary, byte_size(binary) - padding, padding) ==
           :binary.copy(<<padding>>, padding) do
      :binary.part(binary, 0, byte_size(binary) - padding)
    else
      raise ArgumentError, "encrypted setting payload has invalid padding"
    end
  end
end
