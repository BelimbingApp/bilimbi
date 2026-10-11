defmodule Bilimbi.Base.Integration do
  @moduledoc """
  General incoming and outgoing exchange log. The durable relation keeps its
  Belimbing name; direction identifies both kinds of exchange. Integration owns
  transport measurements, never business retries, API authentication or mutation
  audit. Bodies and headers are omitted unless a caller opts into structured,
  bounded, mandatory-redacted previews.

  `record_incoming/2` is the API adapter seam. Call after dispatch with the
  authenticated scope, method, endpoint or operation, status and duration_ms.
  Connection, agent and run identifiers are observational fields, not authority.
  The person and impersonator come only from the scope's sealed actor.

  `request/3` preserves Req's result. Anonymous system traffic uses
  `request_system/2` and is visible only to the platform operator. A persistence
  failure raises rather than silently losing evidence of an external call;
  callers must not retry a consequential command merely because logging failed.
  """

  import Ecto.Query
  alias Bilimbi.Base.{Authz, Repo, Settings, Tenancy}
  alias Bilimbi.Base.Database.WriteCapture
  alias Bilimbi.Base.Integration.{Exchange, Redaction}
  alias Bilimbi.Base.Tenancy.Scope

  @list "admin.system.outbound-exchange.list"
  @payload "admin.system.outbound-exchange.payload.view"
  @delete "admin.system.outbound-exchange.delete"
  @payload_fields ~w(request_headers request_body response_headers response_body metadata)a
  @summary_fields ~w(id tenant_id direction system provider operation endpoint method host path response_status duration_ms outcome error_class error_message owner_type owner_id person_id impersonator_id connection_id agent_id run_id occurred_at)a

  def request(%Scope{} = scope, context, options), do: perform_request(scope, context, options)
  def request_system(context, options), do: perform_request(nil, context, options)

  defp perform_request(scope, context, options) when is_map(context) and is_list(options) do
    request = Req.new(Keyword.put_new(options, :retry, false))
    started = System.monotonic_time(:millisecond)
    result = dispatch(request)
    elapsed = max(System.monotonic_time(:millisecond) - started, 0)

    attrs =
      Map.merge(context, %{
        method: request.method |> to_string() |> String.upcase(),
        endpoint: URI.to_string(request.url),
        duration_ms: elapsed,
        response_status: response_status(result),
        error_class: error_class(result),
        request_headers: request.headers,
        request_body: Keyword.get(options, :json),
        response_headers: response_value(result, :headers),
        response_body: response_value(result, :body)
      })

    {:ok, _id} = record(scope, "outgoing", attrs)
    result
  end

  # Catch only transport failures; bad Req options and programming errors stay errors.
  defp dispatch(request) do
    Req.request(request)
  rescue
    exception in [Mint.TransportError, Mint.HTTPError, Req.TransportError] -> {:error, exception}
  end

  defp response_status({:ok, response}), do: response.status
  defp response_status({:error, _}), do: nil
  defp response_value({:ok, response}, key), do: Map.get(response, key)
  defp response_value({:error, _}, _key), do: nil
  defp error_class({:ok, _}), do: nil
  defp error_class({:error, %{__struct__: module}}), do: inspect(module)
  defp error_class({:error, _}), do: "transport_error"

  def record_incoming(%Scope{} = scope, attrs) when is_map(attrs),
    do: record(scope, "incoming", attrs)

  @doc "Records a call that the API edge could not associate with a tenant (for example a refused credential). Operator-only visibility; no person is asserted."
  def record_incoming_system(attrs) when is_map(attrs), do: record(nil, "incoming", attrs)

  defp record(scope, direction, attrs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    endpoint = Redaction.endpoint(Map.get(attrs, :endpoint, Map.get(attrs, :operation, "/")))
    uri = URI.parse(endpoint)
    status = Map.get(attrs, :response_status)
    retain? = Map.get(attrs, :retain_payload, false) == true
    actor = if scope, do: Scope.actor(scope)

    values =
      attrs
      |> Map.take(
        ~w(system provider operation owner_type owner_id connection_id agent_id run_id correlation_id)a
      )

    values =
      Enum.reduce([:connection_id, :agent_id, :run_id], values, fn key, values ->
        Map.update(values, key, nil, fn
          id when is_integer(id) -> Integer.to_string(id)
          id -> id
        end)
      end)

    values =
      Map.merge(values, %{
        id: "ix_" <> Base.encode32(:crypto.strong_rand_bytes(16), padding: false),
        tenant_id: if(scope, do: Scope.tenant_id(scope)),
        direction: direction,
        system:
          Map.get(attrs, :system, if(direction == "incoming", do: "bilimbi", else: "external")),
        operation: Map.get(attrs, :operation, uri.path || "/"),
        transport: "http",
        protocol: "rest",
        endpoint: endpoint,
        host: uri.host,
        path: uri.path || "/",
        method: if(Map.get(attrs, :method), do: attrs.method |> to_string() |> String.upcase()),
        response_status: status,
        duration_ms: Map.get(attrs, :duration_ms),
        person_id: if(actor, do: actor.user_id),
        impersonator_id: if(actor, do: actor.impersonator_id),
        outcome:
          cond do
            is_integer(status) and status >= 400 -> "http_error"
            Map.get(attrs, :error_class) -> "connection_error"
            is_nil(status) -> "unknown"
            true -> "success"
          end,
        error_class: Map.get(attrs, :error_class),
        # Raw exception messages may embed credentials or complete URLs.
        error_message:
          if(Map.get(attrs, :error_class),
            do: "Exchange failed; inspect the caller's operational outcome."
          ),
        retry_count: 0,
        fallback_used: false,
        request_body_truncated: false,
        response_body_truncated: false,
        occurred_at: now,
        created_at: now,
        updated_at: now
      })

    values =
      Enum.reduce(@payload_fields, values, fn key, values ->
        Map.put(values, key, if(retain?, do: Redaction.structured(Map.get(attrs, key))))
      end)

    # Exchange insertion is machine measurement, not an actor's mutation.
    # Manual deletion stays captured; there is no schema-wide audit exclusion.
    changeset =
      Ecto.Changeset.change(%Exchange{}, values)
      |> Ecto.Changeset.validate_required([:system, :operation, :endpoint])
      |> Ecto.Changeset.validate_number(:duration_ms, greater_than_or_equal_to: 0)
      |> Ecto.Changeset.validate_number(:response_status,
        greater_than_or_equal_to: 100,
        less_than_or_equal_to: 599
      )

    case WriteCapture.without_capture(fn -> Repo.insert(changeset) end) do
      {:ok, row} -> {:ok, row.id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def list_page(%Scope{} = scope, opts \\ []) do
    with :ok <- authorize(scope, @list) do
      opts =
        Keyword.validate!(opts,
          page: 1,
          page_size: 25,
          direction: "outgoing",
          status: "",
          http_status: "",
          search: "",
          actor: "",
          since: "",
          until: ""
        )

      page = opts[:page]
      size = opts[:page_size]

      if not (is_integer(page) and page > 0 and size in [25, 50, 100, 300]),
        do: raise(ArgumentError, "invalid page")

      query = visible(scope) |> filters(opts)
      total = Repo.aggregate(query, :count, :id)

      entries =
        query
        |> order_by([e], desc: e.occurred_at, desc: e.id)
        |> limit(^size)
        |> offset(^((page - 1) * size))
        |> select([e], map(e, ^@summary_fields))
        |> Repo.all()
        |> Enum.map(&summary/1)

      {:ok,
       %{
         entries: entries,
         total_entries: total,
         total_pages: div(total + size - 1, size),
         page: page,
         page_size: size,
         has_prev?: page > 1,
         has_next?: page * size < total
       }}
    end
  end

  def get_exchange(%Scope{} = scope, id) when is_binary(id) do
    with :ok <- authorize(scope, @list) do
      case visible(scope)
           |> where([e], e.id == ^id)
           |> select([e], map(e, ^@summary_fields))
           |> Repo.one() do
        nil -> {:error, :not_found}
        row -> {:ok, summary(row)}
      end
    end
  end

  def payload(%Scope{} = scope, id) when is_binary(id) do
    with :ok <- authorize(scope, @list), :ok <- authorize(scope, @payload) do
      case visible(scope)
           |> where([e], e.id == ^id)
           |> select([e], map(e, ^@payload_fields))
           |> Repo.one() do
        nil -> {:error, :not_found}
        row -> {:ok, Map.new(row, fn {key, value} -> {key, Redaction.inspect_stored(value)} end)}
      end
    end
  end

  def delete_exchange(%Scope{} = scope, id) when is_binary(id) do
    with :ok <- authorize(scope, @delete) do
      {count, _} = visible(scope) |> where([e], e.id == ^id) |> Repo.delete_all()
      if count == 1, do: :ok, else: {:error, :not_found}
    end
  end

  # Imported endpoints and exception messages predate mandatory redaction here.
  defp summary(row) do
    %{
      row
      | endpoint: Redaction.endpoint(row.endpoint),
        error_message: if(row.error_class, do: "Exchange failed")
    }
  end

  defp authorize(scope, capability) do
    if Authz.can(scope, capability).allowed, do: :ok, else: {:error, :forbidden}
  end

  defp visible(scope) do
    query = Tenancy.scope_query(Exchange, scope)
    # Belimbing's operator exception: inspect all tenants and unknown legacy
    # ownership. Only the sealed operator scope widens the tenant predicate.
    if Scope.platform_operator?(scope), do: exclude(query, :where), else: query
  end

  defp filters(query, opts) do
    direction = opts[:direction]
    if direction not in ["incoming", "outgoing"], do: raise(ArgumentError, "invalid direction")
    query = where(query, [e], e.direction == ^direction)

    query =
      if opts[:status] in ~w(success http_error connection_error unknown),
        do: where(query, [e], e.outcome == ^opts[:status]),
        else: query

    pattern = "%#{opts[:search]}%"

    query =
      if opts[:search] != "",
        do:
          where(
            query,
            [e],
            ilike(e.host, ^pattern) or ilike(e.operation, ^pattern) or ilike(e.path, ^pattern)
          ),
        else: query

    query =
      case Integer.parse(to_string(opts[:http_status])) do
        {code, ""} when code in 100..599 -> where(query, [e], e.response_status == ^code)
        _ -> query
      end

    actor = opts[:actor]

    query =
      if actor != "",
        do: where(query, [e], e.agent_id == ^actor or fragment("?::text", e.person_id) == ^actor),
        else: query

    query |> time_filter(opts[:since], :since) |> time_filter(opts[:until], :until)
  end

  defp time_filter(query, "", _), do: query

  defp time_filter(query, value, bound) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        instant = NaiveDateTime.new!(date, ~T[00:00:00])

        if bound == :since,
          do: where(query, [e], e.occurred_at >= ^instant),
          else: where(query, [e], e.occurred_at < ^NaiveDateTime.add(instant, 86400))

      _ ->
        query
    end
  end

  @doc "Globally clears retained previews after the configured TTL; metadata remains for diagnosis."
  def prune_payloads(now \\ NaiveDateTime.utc_now()) do
    days = Settings.get("integration.payload_retention_days")
    cutoff = NaiveDateTime.add(now, -days * 86400)
    # Global machine housekeeping of this module's payloads, independent of
    # manual scoped cleanup. No actor mutation; no extra retained copy in audit.
    {count, _} =
      WriteCapture.without_capture(fn ->
        Repo.update_all(
          from(e in Exchange,
            where:
              e.occurred_at < ^cutoff and
                (not is_nil(e.request_body) or not is_nil(e.response_body) or
                   not is_nil(e.request_headers) or not is_nil(e.response_headers) or
                   not is_nil(e.metadata) or not is_nil(e.traceparent) or not is_nil(e.tracestate))
          ),
          set: [
            request_headers: nil,
            request_body: nil,
            response_headers: nil,
            response_body: nil,
            metadata: nil,
            traceparent: nil,
            tracestate: nil,
            request_body_truncated: false,
            response_body_truncated: false,
            request_body_original_bytes: nil,
            response_body_original_bytes: nil
          ]
        )
      end)

    count
  end
end
