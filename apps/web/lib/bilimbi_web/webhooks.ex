defmodule BilimbiWeb.Webhooks do
  @moduledoc """
  Host inbound webhook boundary. Registrations come from descriptor-owned
  route data: `%{webhook: "identifier", verify: {Module, :verify},
  handle: {Module, :handle}}`.

  The verifier receives an immutable request map with `body` (exact bytes),
  `headers` (all pairs), `remote_ip`, and `method`, returning `{:ok, context}`
  only after authenticating the delivery. The handler receives that request
  and the verified context, returning `:ok`. No callback receives a connection
  or controls the response. Domain modules own signatures, credential lookup,
  replay prevention, tenant resolution and idempotency.

  Never decode, log or audit bodies, headers, signatures, callback errors or
  verified context here. Refusals expose one fixed response. Audit records use
  only registered identifiers and host-owned reason codes.
  """
  import Plug.Conn
  alias Bilimbi.Base.{Audit, Settings}

  @manifest_path Path.expand(
                   "../../../../_build/#{Application.compile_env!(:web, :mix_env)}/bilimbi_routes.exs",
                   __DIR__
                 )
  @external_resource @manifest_path
  {entries, _} = Code.eval_file(@manifest_path)
  @registrations Map.new(Enum.filter(entries, &Map.has_key?(&1, :webhook)), &{&1.webhook, &1})

  def registrations, do: @registrations

  def validate! do
    for {_id, registration} <- @registrations, {key, arity} <- [verify: 1, handle: 2] do
      {module, function} = registration[key]

      unless Code.ensure_loaded?(module) and function_exported?(module, function, arity),
        do:
          raise(
            ArgumentError,
            "webhook callback is not exported: #{inspect(module)}.#{function}/#{arity}"
          )
    end

    :ok
  end

  def deliver(conn, identifier) do
    registration = Map.get(@registrations, identifier)
    outcome = attempt(conn, registration)
    {conn, result} = outcome
    id = if registration, do: identifier, else: "unknown"

    case audit(conn, id, result) do
      {:ok, _} -> respond(conn, result)
      {:error, _} -> respond(conn, :audit_unavailable)
    end
  end

  defp attempt(conn, nil) do
    result =
      case admit(:unknown) do
        :ok -> :unknown_handler
        {:error, :rate_limited} -> :rate_limited
      end

    {conn, result}
  rescue
    _ -> {conn, :host_unavailable}
  catch
    :exit, _ -> {conn, :host_unavailable}
  end

  defp attempt(conn, registration) do
    with :ok <- admit(registration.webhook),
         {:ok, body, conn} <- read_body(conn, Settings.get("webhooks.max_bytes"), []) do
      request = %{
        body: body,
        headers: conn.req_headers,
        remote_ip: conn.remote_ip,
        method: conn.method
      }

      result =
        with {:ok, context} <- callback(registration.verify, [request]),
             :ok <- callback(registration.handle, [request, context]) do
          :accepted
        else
          _ -> :callback_refused
        end

      {conn, result}
    else
      {:error, reason, conn} -> {conn, reason}
      {:error, :rate_limited} -> {conn, :rate_limited}
    end
  rescue
    _ -> {conn, :host_unavailable}
  catch
    :exit, _ -> {conn, :host_unavailable}
  end

  defp admit(identifier) do
    BilimbiWeb.WebhookRateLimit.admit(
      identifier,
      Settings.get("webhooks.rate_limit"),
      Settings.get("webhooks.window_ms")
    )
  end

  defp read_body(conn, remaining, chunks) do
    case Plug.Conn.read_body(conn,
           length: remaining + 1,
           read_length: remaining + 1,
           read_timeout: Settings.get("webhooks.read_timeout_ms")
         ) do
      {status, chunk, conn} when status in [:ok, :more] ->
        remaining = remaining - byte_size(chunk)

        cond do
          remaining < 0 -> {:error, :body_too_large, conn}
          status == :ok -> {:ok, IO.iodata_to_binary(Enum.reverse([chunk | chunks])), conn}
          true -> read_body(conn, remaining, [chunk | chunks])
        end

      {:error, _} ->
        {:error, :body_unreadable, conn}
    end
  rescue
    _ -> {:error, :body_unreadable, conn}
  end

  defp callback({module, function}, args) do
    apply(module, function, args)
  rescue
    _ -> {:error, :callback_failed}
  catch
    _, _ -> {:error, :callback_failed}
  end

  defp audit(conn, id, result) do
    Audit.record_action(:unscoped, %{
      actor_type: "guest",
      actor_id: 0,
      event: "webhook.delivery",
      ip_address: conn.remote_ip,
      occurred_at: NaiveDateTime.utc_now(),
      is_retained: false,
      payload: %{
        "handler" => id,
        "reason" => Atom.to_string(result),
        "result" => if(result == :accepted, do: "succeeded", else: "refused")
      }
    })
  rescue
    _ -> {:error, :audit_unavailable}
  catch
    :exit, _ -> {:error, :audit_unavailable}
  end

  defp respond(conn, result) do
    {status, body} =
      if result == :accepted,
        do: {202, ~s({"status":"accepted"})},
        else: {403, ~s({"error":"delivery_refused"})}

    conn |> put_resp_content_type("application/json") |> send_resp(status, body)
  end
end
