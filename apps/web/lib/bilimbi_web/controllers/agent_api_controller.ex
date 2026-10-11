defmodule BilimbiWeb.AgentApiController do
  use BilimbiWeb, :controller
  alias Bilimbi.Base.AgentApi

  def search(conn, params) do
    words = Map.get(params, "q", "")
    limit = Bilimbi.Base.UI.Params.positive_integer(Map.get(params, "limit", 10))
    kind = Map.get(params, "kind")
    include = Map.get(params, "include_unavailable", "false")

    if is_binary(words) and is_integer(limit) and limit <= 50 and
         kind in [nil, "read", "write"] and include in [true, false, "true", "false"] do
      opts = [limit: limit, include_unavailable: include in [true, "true"]]

      opts =
        case kind do
          "read" -> Keyword.put(opts, :kind, :read)
          "write" -> Keyword.put(opts, :kind, :write)
          nil -> opts
        end

      json(conn, %{result: wire(AgentApi.search(conn.assigns.agent_scope, words, opts))})
    else
      conn |> put_status(400) |> json(%{error: "invalid_request"})
    end
  end

  def describe(conn, %{"key" => key}),
    do: reply(conn, AgentApi.describe(conn.assigns.agent_scope, key))

  def guide(conn, %{"key" => key}), do: reply(conn, AgentApi.guide(conn.assigns.agent_scope, key))

  def invoke(conn, %{"key" => key, "input" => input}) when is_map(input) do
    conn = Plug.Conn.assign(conn, :agent_operation, key)
    reply(conn, AgentApi.call(conn.assigns.agent_scope, key, input))
  end

  def invoke(conn, _), do: conn |> put_status(400) |> json(%{error: "invalid_request"})
  defp reply(conn, {:ok, result}), do: json(conn, wire(result))

  defp reply(conn, {:error, {:invalid_input, fields}}),
    do: conn |> put_status(422) |> json(%{error: "invalid_input", fields: fields})

  defp reply(conn, {:error, {:forbidden, reason}}),
    do: conn |> put_status(403) |> json(%{error: "forbidden", reason: reason})

  defp reply(conn, {:error, reason})
       when reason in [:unknown_operation, :unknown_guide, :not_found],
       do: conn |> put_status(404) |> json(%{error: reason})

  defp reply(conn, {:error, :writes_not_enabled}),
    do: conn |> put_status(409) |> json(%{error: "writes_not_enabled"})

  defp reply(conn, {:error, _}), do: conn |> put_status(422) |> json(%{error: "rejected"})
  # Registry metadata contains tuples (not JSON values); preserve their named
  # refusal rather than relying on an encoder's unsupported tuple behavior.
  defp wire({:refused, reason}), do: %{refused: reason}
  defp wire(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, wire(v)} end)
  defp wire(value) when is_list(value), do: Enum.map(value, &wire/1)
  defp wire(value), do: value
end
