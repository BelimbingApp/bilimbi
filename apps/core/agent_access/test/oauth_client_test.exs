defmodule Bilimbi.Core.AgentAccess.OAuthClientTest do
  use ExUnit.Case, async: true
  alias Bilimbi.Core.AgentAccess.OAuthClient

  test "only exact HTTPS callbacks and bounded display names can be registered" do
    client = %{"name" => "ChatGPT", "redirect_uris" => ["https://chatgpt.com/callback"]}
    assert OAuthClient.valid_clients?(%{"chatgpt" => client})
    assert OAuthClient.valid_clients?(%{})
    refute OAuthClient.valid_clients?(%{"bilimbi-native" => client})
    refute OAuthClient.valid_clients?(%{"chatgpt" => Map.put(client, "client_secret", "unused")})

    for callback <- [
          "http://client.test/callback",
          "https://*.test/callback",
          "https://client.test/*",
          "https://user@client.test/callback",
          "https://client.test/callback#fragment"
        ] do
      refute OAuthClient.valid_clients?(%{"chatgpt" => %{client | "redirect_uris" => [callback]}})
    end

    for name <- ["", "  ", String.duplicate("a", 256)] do
      refute OAuthClient.valid_clients?(%{"chatgpt" => %{client | "name" => name}})
    end
  end

  test "S256 proof matches the RFC 7636 test vector and rejects malformed or mismatched verifiers" do
    verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    assert OAuthClient.proof?(verifier, challenge)

    for invalid <- [
          nil,
          "short",
          String.duplicate("a", 129),
          String.duplicate("!", 43),
          String.duplicate("b", 43)
        ] do
      refute OAuthClient.proof?(invalid, challenge)
    end
  end
end
