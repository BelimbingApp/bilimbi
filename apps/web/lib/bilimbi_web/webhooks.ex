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
  only registered identifiers and host-owned reason codes. Admission and
  aggregated refusal records belong to `BilimbiWeb.WebhookRateLimit`.
  """
  import Plug.Conn
  alias Bilimbi.Base.Audit
  alias BilimbiWeb.WebhookRateLimit

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
    # Match the registry rather than calling `Map.get/2`: an installation with
    # no webhook module compiles the attribute to the literal `%{}`, and the
    # type checker then proves a `Map.get/2` lookup always returns `nil`,
    # which fails `mix compile --warnings-as-errors`. The match says the same
    # thing honestly: an unregistered identifier falls through to "unknown".
    {handler, registration} =
      case @registrations do
        %{^identifier => registration} -> {identifier, registration}
        %{} -> {"unknown", nil}
      end

    {conn, result, record} = attempt(conn, registration)

    if record == :aggregated or match?({:ok, _}, audit(conn, handler, result)),
      do: respond(conn, result),
      else: respond(conn, :audit_unavailable)
  end

  defp attempt(conn, nil) do
    :ok = WebhookRateLimit.refuse("unknown", :unknown_handler)
    {conn, :unknown_handler, :aggregated}
  rescue
    _ -> {conn, :host_unavailable, :audit}
  catch
    :exit, _ -> {conn, :host_unavailable, :audit}
  end

  defp attempt(conn, registration) do
    case WebhookRateLimit.admit_sender(registration.webhook, conn.remote_ip) do
      {:ok, settings} -> verify(conn, registration, settings)
      {:error, :rate_limited} -> {conn, :rate_limited, :aggregated}
    end
  rescue
    _ -> {conn, :host_unavailable, :audit}
  catch
    :exit, _ -> {conn, :host_unavailable, :audit}
  end

  defp verify(conn, registration, settings) do
    case read_body(conn, settings, settings.max_bytes, []) do
      {:ok, body, conn} ->
        request = %{
          body: body,
          headers: conn.req_headers,
          remote_ip: conn.remote_ip,
          method: conn.method
        }

        case callback(registration.verify, [request]) do
          {:ok, context} -> handle(conn, registration, request, context)
          _ -> {conn, :verification_refused, :audit}
        end

      {:error, reason, conn} ->
        {conn, reason, :audit}
    end
  end

  defp handle(conn, registration, request, context) do
    case WebhookRateLimit.admit_verified(registration.webhook) do
      :ok ->
        result =
          if callback(registration.handle, [request, context]) == :ok,
            do: :accepted,
            else: :handler_refused

        {conn, result, :audit}

      {:error, :rate_limited} ->
        {conn, :rate_limited, :aggregated}
    end
  end

  defp read_body(conn, settings, remaining, chunks) do
    case Plug.Conn.read_body(conn,
           length: remaining + 1,
           read_length: remaining + 1,
           read_timeout: settings.read_timeout_ms
         ) do
      {status, chunk, conn} when status in [:ok, :more] ->
        remaining = remaining - byte_size(chunk)

        cond do
          remaining < 0 -> {:error, :body_too_large, conn}
          status == :ok -> {:ok, IO.iodata_to_binary(Enum.reverse([chunk | chunks])), conn}
          true -> read_body(conn, settings, remaining, [chunk | chunks])
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

  defp audit(conn, handler, result) do
    Audit.record_action(:unscoped, %{
      actor_type: "guest",
      actor_id: 0,
      event: "webhook.delivery",
      ip_address: conn.remote_ip,
      occurred_at: NaiveDateTime.utc_now(),
      is_retained: false,
      payload: %{
        "handler" => handler,
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
