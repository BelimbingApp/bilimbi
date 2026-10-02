defmodule BilimbiWeb.WebhookRateLimit do
  @moduledoc """
  Atomic per-node, fixed-window webhook admission. A window opens on the first
  delivery after the previous one closed, reads the `webhooks.*` settings once
  and holds them until it closes. Within a window it counts:

    * attempts per sender (remote IP) per handler, before the body is read;
    * failed attempts per handler, the first `failure_limit` of which the
      caller audits individually;
    * verified deliveries per handler.

  Failures never consume verified capacity. Refusals absorbed here (rate
  limits, unknown handlers and failures past the failure limit) become one
  audit row per handler and reason, with a count, when the window closes.
  Keys are restricted to compiled registrations, one unknown-handler bucket
  and the senders seen in the open window; closing clears all state.
  """
  use GenServer
  alias Bilimbi.Base.{Audit, Settings}

  @settings [
    :max_bytes,
    :rate_limit,
    :sender_rate_limit,
    :failure_limit,
    :window_ms,
    :read_timeout_ms
  ]

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def admit_sender(handler, remote_ip), do: call({:sender, handler, remote_ip})
  def admit_verified(handler), do: call({:verified, handler})
  def record_failure(handler, reason), do: call({:failed, handler, reason})
  def refuse(handler, reason), do: call({:refuse, handler, reason})

  defp call(request) do
    case GenServer.call(__MODULE__, request) do
      {:error, :settings_unavailable} -> exit(:settings_unavailable)
      reply -> reply
    end
  end

  @impl true
  def init(_opts), do: {:ok, nil}

  @impl true
  def handle_call(request, from, nil) do
    case open() do
      {:ok, state} -> handle_call(request, from, state)
      :error -> {:reply, {:error, :settings_unavailable}, nil}
    end
  end

  def handle_call({:sender, handler, remote_ip}, _from, state) do
    case take(state, {:sender, handler, remote_ip}, :sender_rate_limit) do
      {:ok, state} -> {:reply, {:ok, state.settings}, state}
      :exhausted -> {:reply, {:error, :rate_limited}, absorb(state, handler, :rate_limited)}
    end
  end

  def handle_call({:verified, handler}, _from, state) do
    case take(state, {:verified, handler}, :rate_limit) do
      {:ok, state} -> {:reply, :ok, state}
      :exhausted -> {:reply, {:error, :rate_limited}, absorb(state, handler, :rate_limited)}
    end
  end

  def handle_call({:failed, handler, reason}, _from, state) do
    case take(state, {:failed, handler}, :failure_limit) do
      {:ok, state} -> {:reply, :audit, state}
      :exhausted -> {:reply, :aggregated, absorb(state, handler, reason)}
    end
  end

  def handle_call({:refuse, handler, reason}, _from, state),
    do: {:reply, :ok, absorb(state, handler, reason)}

  @impl true
  def handle_info(:close, nil), do: {:noreply, nil}

  def handle_info(:close, state) do
    Process.cancel_timer(state.timer)
    for {{handler, reason}, count} <- state.refused, do: record(handler, reason, count)
    {:noreply, nil}
  end

  defp open do
    settings = Map.new(@settings, &{&1, Settings.get("webhooks.#{&1}")})
    timer = Process.send_after(self(), :close, settings.window_ms)
    {:ok, %{settings: settings, timer: timer, counts: %{}, refused: %{}}}
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  defp take(state, key, limit) do
    count = Map.get(state.counts, key, 0)

    if count < Map.fetch!(state.settings, limit),
      do: {:ok, put_in(state, [:counts, key], count + 1)},
      else: :exhausted
  end

  defp absorb(state, handler, reason),
    do: update_in(state, [:refused, {handler, reason}], &((&1 || 0) + 1))

  defp record(handler, reason, count) do
    Audit.record_action(:unscoped, %{
      actor_type: "guest",
      actor_id: 0,
      event: "webhook.delivery",
      occurred_at: NaiveDateTime.utc_now(),
      is_retained: false,
      payload: %{
        "handler" => handler,
        "reason" => Atom.to_string(reason),
        "result" => "refused",
        "count" => count
      }
    })
  rescue
    _ -> {:error, :audit_unavailable}
  catch
    :exit, _ -> {:error, :audit_unavailable}
  end
end
