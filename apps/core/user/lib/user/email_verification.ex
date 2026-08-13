defmodule Bilimbi.Core.User.EmailVerification do
  @moduledoc false

  @salt "bilimbi core user email verification v1"
  @default_max_age 3_600

  @spec sign(pos_integer(), String.t(), String.t(), keyword()) :: String.t()
  def sign(user_id, email, secret, opts \\ [])
      when is_integer(user_id) and user_id > 0 and is_binary(email) and is_list(opts) do
    validate_secret!(secret)
    opts = Keyword.validate!(opts, max_age: @default_max_age, signed_at: nil)

    token_opts =
      [max_age: validate_max_age!(opts[:max_age])]
      |> maybe_put_signed_at(opts[:signed_at])

    Plug.Crypto.sign(secret, @salt, {user_id, email}, token_opts)
  end

  @spec verify(String.t(), String.t(), keyword()) ::
          {:ok, {pos_integer(), String.t()}} | {:error, :invalid_or_expired_token}
  def verify(token, secret, opts \\ []) when is_binary(token) and is_list(opts) do
    validate_secret!(secret)
    opts = Keyword.validate!(opts, max_age: @default_max_age)

    case Plug.Crypto.verify(secret, @salt, token, max_age: validate_max_age!(opts[:max_age])) do
      {:ok, {user_id, email}}
      when is_integer(user_id) and user_id > 0 and is_binary(email) ->
        {:ok, {user_id, email}}

      _invalid ->
        {:error, :invalid_or_expired_token}
    end
  end

  defp validate_secret!(secret) when is_binary(secret) and byte_size(secret) >= 32, do: :ok

  defp validate_secret!(_secret) do
    raise ArgumentError, "email verification secret must contain at least 32 bytes"
  end

  defp validate_max_age!(seconds) when is_integer(seconds) and seconds > 0, do: seconds
  defp validate_max_age!(_seconds), do: raise(ArgumentError, "token max age must be positive")

  defp maybe_put_signed_at(opts, nil), do: opts

  defp maybe_put_signed_at(opts, signed_at) when is_integer(signed_at),
    do: Keyword.put(opts, :signed_at, signed_at)

  defp maybe_put_signed_at(_opts, _signed_at) do
    raise ArgumentError, "token signed_at must be an integer number of seconds"
  end
end
