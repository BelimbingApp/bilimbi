defmodule Bilimbi.Core.AgentAccess.OAuthClient do
  @moduledoc """
  Exact, operator-configured public OAuth clients. No dynamic registration,
  caller-chosen callback, wildcard or remote metadata fetch can add a client.
  PKCE and the MCP resource are mandatory; the protocol scope delegates only
  the person's existing Agent API reach, never a new authorization grant.
  """
  alias Bilimbi.Base.Settings

  def valid_clients?(clients) when is_map(clients) do
    Enum.all?(clients, fn {id, client} ->
      is_binary(id) and byte_size(id) in 1..255 and id != "bilimbi-native" and
        is_map(client) and map_size(client) == 2 and is_binary(client["name"]) and
        byte_size(client["name"]) in 1..255 and
        String.printable?(client["name"]) and String.trim(client["name"]) != "" and
        is_list(client["redirect_uris"]) and client["redirect_uris"] != [] and
        Enum.all?(client["redirect_uris"], &valid_redirect?/1)
    end)
  end

  def valid_clients?(_), do: false

  def request(params, resource) when is_map(params) and is_binary(resource) do
    client = Map.get(Settings.get("agent_access.oauth_clients"), params["client_id"])

    cond do
      not is_map(client) ->
        {:error, :invalid_client}

      params["redirect_uri"] not in client["redirect_uris"] ->
        {:error, :invalid_redirect_uri}

      params["response_type"] != "code" ->
        {:error, :unsupported_response_type}

      params["resource"] != resource ->
        {:error, :invalid_target}

      Map.get(params, "scope", "bilimbi") != "bilimbi" ->
        {:error, :invalid_scope}

      params["code_challenge_method"] != "S256" or not challenge?(params["code_challenge"]) ->
        {:error, :invalid_request}

      not state?(Map.get(params, "state", "")) ->
        {:error, :invalid_request}

      true ->
        {:ok,
         params
         |> Map.take(
           ~w(client_id redirect_uri code_challenge code_challenge_method state response_type resource)
         )
         |> Map.put("state", Map.get(params, "state", ""))
         |> Map.put("scope", "bilimbi")
         |> Map.put("client_name", client["name"])}
    end
  end

  def request(_, _), do: {:error, :invalid_request}

  def proof?(verifier, challenge)
      when is_binary(verifier) and byte_size(verifier) in 43..128 and is_binary(challenge) do
    digest = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
    Regex.match?(~r/\A[A-Za-z0-9._~-]{43,128}\z/, verifier) and digest == challenge
  end

  def proof?(_, _), do: false
  defp challenge?(value), do: is_binary(value) and Regex.match?(~r/\A[A-Za-z0-9_-]{43}\z/, value)
  defp state?(value), do: is_binary(value) and byte_size(value) <= 1024

  defp valid_redirect?(value) when is_binary(value) do
    uri = URI.parse(value)

    uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and
      is_nil(uri.userinfo) and is_nil(uri.fragment) and not String.contains?(value, "*")
  end

  defp valid_redirect?(_), do: false
end
