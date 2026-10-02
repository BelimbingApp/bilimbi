defmodule BilimbiWeb.WebhookExample do
  @moduledoc false
  # Test-only HMAC demonstration. Production modules must resolve secrets from
  # their encrypted Settings definitions and implement replay protection.
  def verify(request) do
    signature =
      :crypto.mac(:hmac, :sha256, "test-only-key", request.body) |> Base.encode16(case: :lower)

    case List.keyfind(request.headers, "x-signature", 0) do
      {_, supplied} when byte_size(supplied) == byte_size(signature) ->
        if Plug.Crypto.secure_compare(supplied, signature), do: {:ok, :verified}, else: :refused

      _ ->
        :refused
    end
  end

  def handle(%{headers: headers, body: body}, :verified) do
    case List.keyfind(headers, "x-test-outcome", 0) do
      {_, "raise"} ->
        raise "private error must never escape"

      {_, "refuse"} ->
        :refused

      _ ->
        send(self(), {:webhook_body, body})
        :ok
    end
  end
end
