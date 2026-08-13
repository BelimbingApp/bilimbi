defmodule Bilimbi.Core.User.Password do
  @moduledoc false

  @argon2_prefixes ["$argon2id$", "$argon2i$", "$argon2d$"]
  @bcrypt_prefixes ["$2a$", "$2b$", "$2y$"]

  @spec hash(String.t()) :: String.t()
  def hash(password) when is_binary(password) and byte_size(password) > 0 do
    Argon2.hash_pwd_salt(password)
  end

  @spec valid?(String.t(), String.t()) :: boolean()
  def valid?(password, hash)
      when is_binary(password) and byte_size(password) > 0 and is_binary(hash) do
    cond do
      starts_with_any?(hash, @argon2_prefixes) ->
        Argon2.verify_pass(password, hash)

      starts_with_any?(hash, @bcrypt_prefixes) ->
        Bcrypt.verify_pass(password, normalize_bcrypt(hash))

      true ->
        no_user_verify()
    end
  rescue
    ArgumentError -> false
    ErlangError -> false
  end

  def valid?(_password, _hash), do: no_user_verify()

  @spec legacy?(String.t()) :: boolean()
  def legacy?(hash) when is_binary(hash), do: starts_with_any?(hash, @bcrypt_prefixes)
  def legacy?(_hash), do: false

  @spec no_user_verify() :: false
  def no_user_verify do
    Argon2.no_user_verify()
    false
  end

  defp normalize_bcrypt("$2y$" <> remainder), do: "$2b$" <> remainder
  defp normalize_bcrypt(hash), do: hash
  defp starts_with_any?(value, prefixes), do: Enum.any?(prefixes, &String.starts_with?(value, &1))
end
